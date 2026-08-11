import Foundation
import LogicEngineCore
import LogicIR
import LogicSimulation
import CircuiteFoundation
import CircuiteFoundationCrypto

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
    ) async throws -> LogicBoundedTemporalEquivalenceResult {
        let startedAt = Date()
        do {
            try request.validate()
            try checkCancellation()
            let referenceBinding = try LogicArtifactBinding.require(
                request.referenceDesign.artifact,
                in: request.inputBindings
            )
            let implementationBinding = try LogicArtifactBinding.require(
                request.implementationDesign.artifact,
                in: request.inputBindings
            )
            let referenceDesign = try decodeDesign(referenceBinding)
            let implementationDesign = try decodeDesign(implementationBinding)
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
            let stimulusDigest = try SHA256ContentDigester()
                .digest(data: stimulusData, using: .sha256)
                .hexadecimalValue

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
            let referenceReportBinding = try LogicArtifactBinding.require(
                rawReferenceReportReference,
                in: referenceEnvelope.artifactBindings
            )
            let implementationReportBinding = try LogicArtifactBinding.require(
                rawImplementationReportReference,
                in: implementationEnvelope.artifactBindings
            )
            let referenceReport = try decodeReport(referenceReportBinding)
            let implementationReport = try decodeReport(implementationReportBinding)
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
            let reportBinding = try writeJSON(
                report,
                fileName: "logic-bounded-temporal-equivalence-report.json",
                request: request
            )
            let counterexampleBinding: LogicArtifactBinding?
            if differences.isEmpty {
                counterexampleBinding = nil
            } else {
                counterexampleBinding = try writeJSON(
                    report,
                    fileName: "logic-bounded-temporal-counterexample.json",
                    request: request
                )
            }
            let simulationArtifacts = referenceEnvelope.artifactBindings
                + implementationEnvelope.artifactBindings
            let diagnostics: [DesignDiagnostic]
            if differences.isEmpty {
                diagnostics = [DesignDiagnostic(
                    severity: .information,
                    code: "LOGIC_BOUNDED_TEMPORAL_EQUIVALENCE_PROVED",
                    message: "The reference and implementation traces matched for the declared output signals and finite sample bound.",
                    suggestedActions: ["retain_bounded_equivalence_report", "request_qualified_unbounded_proof"]
                )]
            } else {
                diagnostics = [DesignDiagnostic(
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
                referenceSimulationReport: referenceReportBinding.reference,
                implementationSimulationReport: implementationReportBinding.reference,
                equivalenceReport: reportBinding.reference,
                counterexample: counterexampleBinding?.reference
            )
            return try LogicBoundedTemporalEquivalenceResult(
                schemaVersion: LogicBoundedTemporalEquivalenceRequest.currentSchemaVersion,
                runID: request.runID,
                status: differences.isEmpty ? .completed : .failed,
                diagnostics: diagnostics,
                artifactBindings: simulationArtifacts + [reportBinding]
                    + (counterexampleBinding.map { [$0] } ?? []),
                provenance: try ExecutionProvenance(
                    producer: ProducerIdentity(
                        kind: .engine,
                        identifier: "LogicBoundedTemporalEquivalence",
                        version: implementationVersion,
                        build: "native-bounded-trace"
                    ),
                    inputs: request.inputs,
                    invocation: ExecutionInvocation.inProcess(
                        entryPoint: "NativeLogicBoundedTemporalEquivalenceEngine.execute"
                    ),
                    randomSeed: nil,
                    startedAt: startedAt,
                    completedAt: Date()
                ),
                payload: payload
            )
        } catch let error as LogicExecutionError {
            return try failureEnvelope(request: request, error: error, startedAt: startedAt)
        } catch {
            throw error
        }
    }

    private func decodeDesign(_ binding: LogicArtifactBinding) throws -> LogicDesignDocument {
        let data = try artifactStore.read(binding)
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
    ) async throws -> LogicSimulationResult {
        try await NativeLogicSimulationEngine(artifactStore: artifactStore).execute(
            LogicSimulationRequest(
                runID: "\(request.runID)-\(role)",
                inputBindings: request.inputBindings,
                design: design,
                stimulus: request.stimulus,
                waveformFormat: .vcd,
                artifactDirectory: outputDirectory
            )
        )
    }

    private func decodeReport(_ binding: LogicArtifactBinding) throws -> LogicSimulationReport {
        let data = try artifactStore.read(binding)
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
    ) throws -> LogicArtifactBinding {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try artifactStore.write(
            encoder.encode(value),
            fileName: fileName,
            outputDirectory: request.artifactDirectory,
            runID: request.runID,
            kind: .report,
            format: .json
        )
    }

    private func digest(of request: LogicBoundedTemporalEquivalenceRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try SHA256ContentDigester()
            .digest(data: try encoder.encode(request), using: .sha256)
            .hexadecimalValue
    }

    private func failureEnvelope(
        request: LogicBoundedTemporalEquivalenceRequest,
        error: LogicExecutionError,
        startedAt: Date
    ) throws -> LogicBoundedTemporalEquivalenceResult {
        try LogicBoundedTemporalEquivalenceResult(
            schemaVersion: LogicBoundedTemporalEquivalenceRequest.currentSchemaVersion,
            runID: request.runID,
            status: LogicDiagnosticFactory.status(for: error),
            diagnostics: [LogicDiagnosticFactory.make(for: error)],
            artifactBindings: [],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "LogicBoundedTemporalEquivalence",
                    version: implementationVersion,
                    build: "native-bounded-trace"
                ),
                inputs: request.inputs,
                invocation: ExecutionInvocation.inProcess(
                    entryPoint: "NativeLogicBoundedTemporalEquivalenceEngine.execute"
                ),
                randomSeed: nil,
                startedAt: startedAt,
                completedAt: Date()
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
