import Foundation
import CircuiteFoundation
import LogicEngineCore
import LogicIR

public struct NativeLogicSimulationEngine: LogicSimulationExecuting {
    public let artifactStore: any LogicArtifactStoring
    public let implementationVersion: String

    public init(
        artifactStore: any LogicArtifactStoring = FileSystemLogicArtifactStore(),
        implementationVersion: String = "1.0.0"
    ) {
        self.artifactStore = artifactStore
        self.implementationVersion = implementationVersion
    }

    public func execute(
        _ request: LogicSimulationRequest
    ) async throws -> LogicSimulationResult {
        let startedAt = Date()
        do {
            try validate(request)
            try checkCancellation()
            for input in request.inputs {
                _ = try artifactStore.read(input)
            }
            let designData = try artifactStore.read(request.design.artifact)
            let designDigest = request.design.artifact.digest.hexadecimalValue
            guard request.design.designDigest == designDigest else {
                throw LogicExecutionError.artifactDigestMismatch(request.design.artifact.locator.location.value)
            }
            let design = try decodeDesign(designData)
            guard design.topDesignName == request.design.topDesignName else {
                throw LogicExecutionError.invalidDesign(
                    "request top design \(request.design.topDesignName) does not match artifact \(design.topDesignName)"
                )
            }
            try design.validateNativeExecutionTopology()
            guard let unsupportedNode = design.nodes.first(where: { !$0.kind.isSupported }) else {
                try checkCancellation()
                let stimulus = try loadStimulus(request.stimulus, design: design)
                let result = try simulate(
                    design: design,
                    stimulus: stimulus,
                    runID: request.runID,
                    waveformFormat: request.waveformFormat
                )
                try checkCancellation()
                return try makeEnvelope(
                    request: request,
                    design: design,
                    result: result,
                    startedAt: startedAt
                )
            }
            throw LogicExecutionError.unsupportedNode(
                nodeID: unsupportedNode.id,
                kind: unsupportedNode.kind.rawValue
            )
        } catch let error as LogicExecutionError {
            return try failureEnvelope(
                request: request,
                error: error,
                startedAt: startedAt
            )
        } catch {
            throw error
        }
    }

    private func validate(_ request: LogicSimulationRequest) throws {
        try request.validate()
    }

    private func decodeDesign(_ data: Data) throws -> LogicDesignDocument {
        do {
            let design = try JSONDecoder().decode(LogicDesignDocument.self, from: data)
            try design.validate()
            return design
        } catch let error as LogicExecutionError {
            throw error
        } catch {
            throw LogicExecutionError.invalidArtifact(
                "design JSON could not be decoded: \(String(reflecting: error))"
            )
        }
    }

    private func loadStimulus(
        _ reference: ArtifactReference?,
        design: LogicDesignDocument
    ) throws -> LogicStimulusDocument {
        guard let reference else {
            let stimulus = LogicStimulusDocument(events: [LogicStimulusEvent(time: 0, assignments: [:])])
            try stimulus.validate(against: design)
            return stimulus
        }
        let data = try artifactStore.read(reference)
        do {
            let stimulus = try JSONDecoder().decode(LogicStimulusDocument.self, from: data)
            try stimulus.validate(against: design)
            return stimulus
        } catch let error as LogicExecutionError {
            throw error
        } catch {
            throw LogicExecutionError.invalidStimulus("stimulus JSON could not be decoded: \(error.localizedDescription)")
        }
    }

    private func simulate(
        design: LogicDesignDocument,
        stimulus: LogicStimulusDocument,
        runID: String,
        waveformFormat: LogicWaveformFormat
    ) throws -> SimulationResult {
        guard waveformFormat == .vcd else {
            throw LogicExecutionError.unsupportedWaveform(waveformFormat.rawValue)
        }
        var values: [String: LogicVector] = [:]
        for signal in design.signals {
            if let initialValue = signal.initialValue {
                values[signal.name] = initialValue
            } else {
                values[signal.name] = try LogicVector.unknown(width: signal.width)
            }
        }
        let eventsByTime = Dictionary(grouping: stimulus.events, by: \.time)
        let assertionTimes = stimulus.assertions.map(\.time)
        let lastEventTime = stimulus.events.map(\.time).max() ?? 0
        let lastRequestedTime = max(lastEventTime, stimulus.endTime ?? lastEventTime)
        var times = Set(eventsByTime.keys).union(assertionTimes)
        times.insert(0)
        times.insert(lastRequestedTime)
        let orderedTimes = times.sorted()
        var previousClockValues: [String: LogicValue] = [:]
        var previousResetValues: [String: LogicValue] = [:]
        var samples: [LogicWaveformSample] = []
        let evaluator = LogicExecutionGraphEvaluator()

        for time in orderedTimes {
            try checkCancellation()
            let events = eventsByTime[time] ?? []
            for event in events {
                for signal in event.assignments.keys.sorted() {
                    guard let value = event.assignments[signal] else { continue }
                    values[signal] = value
                }
            }
            try evaluator.settleCombinational(design: design, values: &values)
            try evaluator.updateSequential(
                design: design,
                values: &values,
                previousClockValues: &previousClockValues,
                previousResetValues: &previousResetValues
            )
            try evaluator.settleCombinational(design: design, values: &values)
            samples.append(LogicWaveformSample(time: time, values: values))
        }

        let sampleByTime = Dictionary(uniqueKeysWithValues: samples.map { ($0.time, $0) })
        let assertionResults = stimulus.assertions.map { assertion in
            let observed = sampleByTime[assertion.time]?.values[assertion.signal]
            return LogicAssertionResult(
                assertionID: assertion.id,
                passed: observed == assertion.expected,
                observed: observed,
                expected: assertion.expected,
                time: assertion.time
            )
        }
        return SimulationResult(
            report: LogicSimulationReport(
                runID: runID,
                eventCount: stimulus.events.count,
                samples: samples,
                assertions: assertionResults
            ),
            finalValues: values,
            timeUnit: stimulus.timeUnit
        )
    }


    private func makeEnvelope(
        request: LogicSimulationRequest,
        design: LogicDesignDocument,
        result: SimulationResult,
        startedAt: Date
    ) throws -> LogicSimulationResult {
        let reportData: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            reportData = try encoder.encode(result.report)
        } catch {
            throw LogicExecutionError.artifactWriteFailed("simulation report encoding failed: \(error.localizedDescription)")
        }
        let waveformData = try makeVCD(
            design: design,
            report: result.report,
            timeUnit: result.timeUnit
        )
        let waveformReference = try artifactStore.write(
            waveformData,
            fileName: "logic-waveform.vcd",
            outputDirectory: request.artifactDirectory,
            runID: request.runID,
            artifactID: "logic-waveform",
            kind: .waveform,
            format: .vcd
        )
        let reportReference = try artifactStore.write(
            reportData,
            fileName: "logic-simulation-report.json",
            outputDirectory: request.artifactDirectory,
            runID: request.runID,
            artifactID: "logic-simulation-report",
            kind: .report,
            format: .json
        )
        let failureCount = result.report.assertions.filter { !$0.passed }.count
        let status: LogicIR.LogicExecutionStatus = failureCount == 0 ? .completed : .failed
        var diagnostics: [DesignDiagnostic] = [
            DesignDiagnostic(
                code: .trusted("logic.simulation.completed"),
                severity: .information,
                summary: "Simulated \(result.report.eventCount) event(s) over \(result.report.samples.count) trace sample(s)."
            ),
        ]
        if failureCount > 0 {
            diagnostics.append(DesignDiagnostic(
                code: .trusted("logic.simulation.assertion-failed"),
                severity: .error,
                summary: "\(failureCount) assertion(s) failed.",
                suggestedActions: [
                    SuggestedAction(code: "logic.simulation.inspect-report", summary: "inspect_assertion_report"),
                    SuggestedAction(code: "logic.simulation.review-waveform", summary: "review_waveform_at_assertion_time")
                ]
            ))
        }
        let payload = LogicSimulationPayload(
            traceCount: result.report.samples.count,
            assertionFailureCount: failureCount,
            eventCount: result.report.eventCount,
            waveform: waveformReference,
            assertionReport: reportReference,
            finalValues: result.finalValues
        )
        return LogicSimulationResult(
            runID: request.runID,
            status: status,
            payload: payload,
            artifacts: [waveformReference, reportReference],
            diagnostics: diagnostics,
            provenance: try makeProvenance(request: request, startedAt: startedAt)
        )
    }

    private func failureEnvelope(
        request: LogicSimulationRequest,
        error: LogicExecutionError,
        startedAt: Date
    ) throws -> LogicSimulationResult {
        let diagnostic = LogicDiagnosticFactory.make(for: error)
        let cancellationReference: ArtifactReference?
        if case .cancelled = error {
            let record = LogicCancellationRecord(
                runID: request.runID,
                engineID: "LogicSimulation",
                reason: error.localizedDescription
            )
            let recordData: Data
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                recordData = try encoder.encode(record)
            } catch {
                throw LogicExecutionError.artifactWriteFailed(
                    "cancellation record encoding failed: \(error.localizedDescription)"
                )
            }
            cancellationReference = try artifactStore.write(
                recordData,
                fileName: "logic-cancellation-record.json",
                outputDirectory: request.artifactDirectory,
                runID: request.runID,
                artifactID: "logic-cancellation-record",
                kind: .report,
                format: .json
            )
        } else {
            cancellationReference = nil
        }
        return LogicSimulationResult(
            runID: request.runID,
            status: LogicDiagnosticFactory.status(for: error),
            payload: LogicSimulationPayload(
                traceCount: 0,
                assertionFailureCount: 0,
                cancellationRecord: cancellationReference
            ),
            artifacts: cancellationReference.map { [$0] } ?? [],
            diagnostics: [diagnostic],
            provenance: try makeProvenance(request: request, startedAt: startedAt)
        )
    }

    private func makeProvenance(
        request: LogicSimulationRequest,
        startedAt: Date
    ) throws -> ExecutionProvenance {
        try ExecutionProvenance(
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "logic-simulation",
                version: implementationVersion
            ),
            inputs: request.inputs,
            randomSeed: request.seed,
            startedAt: startedAt,
            completedAt: Date()
        )
    }

    private func makeVCD(
        design: LogicDesignDocument,
        report: LogicSimulationReport,
        timeUnit: String
    ) throws -> Data {
        let signalNames = design.signals.map(\.name).sorted()
        var identifiers: [String: String] = [:]
        for (index, name) in signalNames.enumerated() {
            identifiers[name] = "s\(index)"
        }
        var lines = [
            "$timescale 1\(timeUnit) $end",
            "$scope module logic $end",
        ]
        for name in signalNames {
            let width = try design.signalWidth(named: name)
            lines.append("$var wire \(width) \(identifiers[name] ?? name) \(name) $end")
        }
        lines.append(contentsOf: ["$upscope $end", "$enddefinitions $end"])
        for sample in report.samples {
            lines.append("#\(sample.time)")
            for name in signalNames {
                guard let value = sample.values[name], let identifier = identifiers[name] else { continue }
                if value.width == 1 {
                    lines.append("\(value.description.lowercased())\(identifier)")
                } else {
                    lines.append("b\(value.description.lowercased()) \(identifier)")
                }
            }
        }
        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw LogicExecutionError.artifactWriteFailed("VCD encoding failed")
        }
        return data
    }

    private func checkCancellation() throws {
        if Task.isCancelled {
            throw LogicExecutionError.cancelled
        }
    }

    private struct SimulationResult: Sendable {
        let report: LogicSimulationReport
        let finalValues: [String: LogicVector]
        let timeUnit: String
    }
}
