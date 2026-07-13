import Foundation
import LogicEngineCore
import LogicIR
import LogicSimulation
import XcircuitePackage

public struct NativeLogicBoundedTemporalEquivalenceEngine: LogicBoundedTemporalEquivalenceExecuting {
    public let artifactStore: any LogicArtifactStoring
    public let implementationVersion: String

    public init(
        artifactStore: any LogicArtifactStoring = FileSystemLogicArtifactStore(),
        implementationVersion: String = "1"
    ) {
        self.artifactStore = artifactStore
        self.implementationVersion = implementationVersion
    }

    public func execute(
        _ request: LogicBoundedTemporalEquivalenceRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicBoundedTemporalEquivalencePayload> {
        let startedAt = Date()
        do {
            try request.validate()
            try checkCancellation()
            let referenceDesign = try decodeDesign(request.referenceDesign.artifact)
            let implementationDesign = try decodeDesign(request.implementationDesign.artifact)
            try validateDesignPair(
                reference: referenceDesign,
                implementation: implementationDesign,
                request: request
            )
            let outputSignals = try outputSignals(
                request: request,
                reference: referenceDesign,
                implementation: implementationDesign
            )
            let stimulusData = try artifactStore.read(request.stimulus)
            let stimulus = try decodeStimulus(stimulusData)
            try stimulus.validate(against: referenceDesign)
            try stimulus.validate(against: implementationDesign)
            let requestDigest = try digest(of: request)
            let stimulusDigest = XcircuiteHasher().sha256(data: stimulusData)

            let baseDirectory = request.artifactDirectory
                ?? ".logic-engine/runs/\(request.runID)/bounded-temporal"
            let referenceEnvelope = try await simulate(
                request: request,
                design: request.referenceDesign,
                role: "reference",
                outputDirectory: baseDirectory + "/reference"
            )
            let implementationEnvelope = try await simulate(
                request: request,
                design: request.implementationDesign,
                role: "implementation",
                outputDirectory: baseDirectory + "/implementation"
            )
            guard referenceEnvelope.status == .completed else {
                throw LogicExecutionError.missingPrerequisite(
                    "reference simulation did not complete for bounded temporal equivalence"
                )
            }
            guard implementationEnvelope.status == .completed else {
                throw LogicExecutionError.missingPrerequisite(
                    "implementation simulation did not complete for bounded temporal equivalence"
                )
            }
            guard let rawReferenceReportReference = referenceEnvelope.payload.assertionReport,
                  let rawImplementationReportReference = implementationEnvelope.payload.assertionReport else {
                throw LogicExecutionError.missingPrerequisite(
                    "bounded temporal equivalence requires both simulation reports"
                )
            }
            let referenceArtifacts = labelArtifacts(referenceEnvelope.artifacts, role: "reference")
            let implementationArtifacts = labelArtifacts(implementationEnvelope.artifacts, role: "implementation")
            let referenceReportReference = labeled(rawReferenceReportReference, role: "reference")
            let implementationReportReference = labeled(rawImplementationReportReference, role: "implementation")
            let referenceReport = try decodeReport(rawReferenceReportReference)
            let implementationReport = try decodeReport(rawImplementationReportReference)
            guard referenceReport.samples.count <= request.sampleLimit,
                  implementationReport.samples.count <= request.sampleLimit else {
                throw LogicExecutionError.missingPrerequisite(
                    "simulation trace exceeds bounded temporal equivalence sample limit \(request.sampleLimit)"
                )
            }

            let differences = compare(
                reference: referenceReport,
                implementation: implementationReport,
                outputSignals: outputSignals
            )
            let status: LogicBoundedTemporalEquivalenceStatus = differences.isEmpty
                ? .proved
                : .counterexample
            let report = LogicBoundedTemporalEquivalenceReport(
                runID: request.runID,
                requestDigest: requestDigest,
                stimulusDigest: stimulusDigest,
                referenceDesignDigest: request.referenceDesign.designDigest,
                implementationDesignDigest: request.implementationDesign.designDigest,
                outputSignals: outputSignals,
                sampleLimit: request.sampleLimit,
                comparedSampleCount: Set(referenceReport.samples.map(\.time))
                    .union(implementationReport.samples.map(\.time)).count,
                differences: differences,
                status: status
            )
            try report.validate()
            let reportReference = try writeJSON(
                report,
                fileName: "logic-bounded-temporal-equivalence-report.json",
                request: request
            )
            let counterexampleReference: XcircuiteFileReference?
            if differences.isEmpty {
                counterexampleReference = nil
            } else {
                counterexampleReference = try writeJSON(
                    report,
                    fileName: "logic-bounded-temporal-counterexample.json",
                    request: request
                )
            }
            let simulationArtifacts = referenceArtifacts + implementationArtifacts
            let diagnostics: [XcircuiteEngineDiagnostic]
            if differences.isEmpty {
                diagnostics = [XcircuiteEngineDiagnostic(
                    severity: .info,
                    code: "LOGIC_BOUNDED_TEMPORAL_EQUIVALENCE_PROVED",
                    message: "The reference and implementation traces matched for the declared output signals and finite sample bound.",
                    suggestedActions: ["retain_bounded_equivalence_report", "request_qualified_unbounded_proof"]
                )]
            } else {
                diagnostics = [XcircuiteEngineDiagnostic(
                    severity: .error,
                    code: "LOGIC_BOUNDED_TEMPORAL_COUNTEREXAMPLE",
                    message: "The reference and implementation traces differ within the declared bounded proof scope.",
                    suggestedActions: ["inspect_bounded_counterexample", "repair_implementation", "request_qualified_unbounded_proof"]
                )]
            }
            let payload = LogicBoundedTemporalEquivalencePayload(
                proofStatus: status,
                comparedSampleCount: report.comparedSampleCount,
                mismatchCount: differences.count,
                outputSignals: outputSignals,
                referenceSimulationReport: referenceReportReference,
                implementationSimulationReport: implementationReportReference,
                equivalenceReport: reportReference,
                counterexample: counterexampleReference
            )
            return XcircuiteEngineResultEnvelope(
                schemaVersion: LogicBoundedTemporalEquivalenceRequest.currentSchemaVersion,
                runID: request.runID,
                status: differences.isEmpty ? .completed : .failed,
                diagnostics: diagnostics,
                artifacts: simulationArtifacts + [reportReference] + (counterexampleReference.map { [$0] } ?? []),
                metadata: XcircuiteEngineExecutionMetadata(
                    engineID: "LogicBoundedTemporalEquivalence",
                    implementationID: "native-bounded-trace",
                    implementationVersion: implementationVersion,
                    startedAt: startedAt,
                    completedAt: Date(),
                    seed: nil
                ),
                payload: payload
            )
        } catch let error as LogicExecutionError {
            return failureEnvelope(request: request, error: error, startedAt: startedAt)
        } catch {
            throw error
        }
    }

    private func decodeDesign(_ reference: XcircuiteFileReference) throws -> LogicDesignDocument {
        let data = try artifactStore.read(reference)
        do {
            let design = try JSONDecoder().decode(LogicDesignDocument.self, from: data)
            try design.validate()
            try design.validateNativeExecutionTopology()
            if let unsupported = design.nodes.first(where: { !$0.kind.isSupported }) {
                throw LogicExecutionError.unsupportedNode(nodeID: unsupported.id, kind: unsupported.kind.rawValue)
            }
            return design
        } catch let error as LogicExecutionError {
            throw error
        } catch {
            throw LogicExecutionError.invalidArtifact(
                "bounded temporal equivalence design JSON could not be decoded: \(error.localizedDescription)"
            )
        }
    }

    private func decodeStimulus(_ data: Data) throws -> LogicStimulusDocument {
        do {
            return try JSONDecoder().decode(LogicStimulusDocument.self, from: data)
        } catch {
            throw LogicExecutionError.invalidStimulus(
                "bounded temporal equivalence stimulus JSON could not be decoded: \(error.localizedDescription)"
            )
        }
    }

    private func validateDesignPair(
        reference: LogicDesignDocument,
        implementation: LogicDesignDocument,
        request: LogicBoundedTemporalEquivalenceRequest
    ) throws {
        guard reference.topDesignName == request.referenceDesign.topDesignName,
              implementation.topDesignName == request.implementationDesign.topDesignName else {
            throw LogicExecutionError.invalidDesign(
                "bounded temporal equivalence artifact top names do not match the request"
            )
        }
        guard reference.topDesignName == implementation.topDesignName else {
            throw LogicExecutionError.invalidDesign(
                "bounded temporal equivalence artifacts have different top design names"
            )
        }
    }

    private func outputSignals(
        request: LogicBoundedTemporalEquivalenceRequest,
        reference: LogicDesignDocument,
        implementation: LogicDesignDocument
    ) throws -> [String] {
        let requested = request.outputSignals.isEmpty
            ? reference.ports.filter { $0.direction == .output }.map(\.name).sorted()
            : request.outputSignals
        guard !requested.isEmpty else {
            throw LogicExecutionError.missingPrerequisite(
                "bounded temporal equivalence requires at least one output signal"
            )
        }
        for signal in requested {
            guard let referencePort = reference.ports.first(where: { $0.name == signal }),
                  let implementationPort = implementation.ports.first(where: { $0.name == signal }),
                  referencePort.direction == .output,
                  implementationPort.direction == .output else {
                throw LogicExecutionError.unknownSignal(signal)
            }
            guard referencePort.width == implementationPort.width else {
                throw LogicExecutionError.vectorWidthMismatch(
                    expected: referencePort.width,
                    actual: implementationPort.width
                )
            }
        }
        return requested
    }

    private func simulate(
        request: LogicBoundedTemporalEquivalenceRequest,
        design: LogicDesignReference,
        role: String,
        outputDirectory: String
    ) async throws -> XcircuiteEngineResultEnvelope<LogicSimulationPayload> {
        try await NativeLogicSimulationEngine(artifactStore: artifactStore).execute(
            LogicSimulationRequest(
                runID: "\(request.runID)-\(role)",
                inputs: request.inputs + [request.stimulus],
                design: design,
                stimulus: request.stimulus,
                waveformFormat: .vcd,
                artifactDirectory: outputDirectory
            )
        )
    }

    private func labelArtifacts(
        _ artifacts: [XcircuiteFileReference],
        role: String
    ) -> [XcircuiteFileReference] {
        artifacts.map { labeled($0, role: role) }
    }

    private func labeled(
        _ reference: XcircuiteFileReference,
        role: String
    ) -> XcircuiteFileReference {
        var labeledReference = reference
        let suffix = reference.artifactID ?? "artifact"
        labeledReference.artifactID = "logic-bounded-" + role + "-" + suffix
        return labeledReference
    }

    private func decodeReport(_ reference: XcircuiteFileReference) throws -> LogicSimulationReport {
        let data = try artifactStore.read(reference)
        do {
            return try JSONDecoder().decode(LogicSimulationReport.self, from: data)
        } catch {
            throw LogicExecutionError.invalidArtifact(
                "bounded temporal equivalence simulation report could not be decoded: \(error.localizedDescription)"
            )
        }
    }

    private func compare(
        reference: LogicSimulationReport,
        implementation: LogicSimulationReport,
        outputSignals: [String]
    ) -> [LogicBoundedTemporalEquivalenceDifference] {
        let referenceSamples = Dictionary(uniqueKeysWithValues: reference.samples.map { ($0.time, $0) })
        let implementationSamples = Dictionary(uniqueKeysWithValues: implementation.samples.map { ($0.time, $0) })
        let times = Set(referenceSamples.keys).union(implementationSamples.keys).sorted()
        var differences: [LogicBoundedTemporalEquivalenceDifference] = []
        for time in times {
            for signal in outputSignals {
                let referenceValue = referenceSamples[time]?.values[signal]
                let implementationValue = implementationSamples[time]?.values[signal]
                guard referenceValue != implementationValue else { continue }
                differences.append(LogicBoundedTemporalEquivalenceDifference(
                    time: time,
                    signal: signal,
                    referenceValue: referenceValue,
                    implementationValue: implementationValue
                ))
            }
        }
        return differences
    }

    private func writeJSON<T: Encodable>(
        _ value: T,
        fileName: String,
        request: LogicBoundedTemporalEquivalenceRequest
    ) throws -> XcircuiteFileReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try artifactStore.write(
            encoder.encode(value),
            fileName: fileName,
            outputDirectory: request.artifactDirectory,
            runID: request.runID,
            artifactID: fileName.replacingOccurrences(of: ".json", with: ""),
            kind: .report,
            format: .json
        )
    }

    private func digest(of request: LogicBoundedTemporalEquivalenceRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return XcircuiteHasher().sha256(data: try encoder.encode(request))
    }

    private func failureEnvelope(
        request: LogicBoundedTemporalEquivalenceRequest,
        error: LogicExecutionError,
        startedAt: Date
    ) -> XcircuiteEngineResultEnvelope<LogicBoundedTemporalEquivalencePayload> {
        XcircuiteEngineResultEnvelope(
            schemaVersion: LogicBoundedTemporalEquivalenceRequest.currentSchemaVersion,
            runID: request.runID,
            status: LogicDiagnosticFactory.status(for: error),
            diagnostics: [LogicDiagnosticFactory.make(for: error)],
            artifacts: [],
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "LogicBoundedTemporalEquivalence",
                implementationID: "native-bounded-trace",
                implementationVersion: implementationVersion,
                startedAt: startedAt,
                completedAt: Date(),
                seed: nil
            ),
            payload: LogicBoundedTemporalEquivalencePayload(
                proofStatus: .blocked,
                comparedSampleCount: 0,
                mismatchCount: 0,
                outputSignals: []
            )
        )
    }

    private func checkCancellation() throws {
        if Task.isCancelled {
            throw LogicExecutionError.cancelled
        }
    }
}
