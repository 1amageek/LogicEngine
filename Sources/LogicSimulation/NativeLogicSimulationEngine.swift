import Foundation
import CircuiteFoundation
import LogicEngineCore
import LogicIR

public struct NativeLogicSimulationEngine: LogicSimulationExecuting {
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
            guard request.design.designRevision?.hexadecimalValue == nil
                || request.design.designRevision?.hexadecimalValue == designDigest else {
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

    private func settleCombinational(
        design: LogicDesignDocument,
        values: inout [String: LogicVector]
    ) throws {
        let combinationalNodes = design.nodes.filter { !$0.kind.isSequential }
        guard !combinationalNodes.isEmpty else { return }
        let maximumIterations = max(1, combinationalNodes.count * 4)
        for _ in 0..<maximumIterations {
            let before = values
            for node in combinationalNodes {
                let output = try evaluate(node: node, design: design, values: values)
                for signal in node.outputs {
                    values[signal] = try output.broadcast(to: design.signalWidth(named: signal))
                }
            }
            if before == values { return }
        }
        throw LogicExecutionError.combinationalCycle
    }

    private func updateSequential(
        design: LogicDesignDocument,
        values: inout [String: LogicVector],
        previousClockValues: inout [String: LogicValue],
        previousResetValues: inout [String: LogicValue]
    ) throws {
        let sampledValues = values
        var pendingValues: [String: LogicVector] = [:]
        var pendingClockValues: [String: LogicValue] = [:]
        for node in design.nodes where node.kind.isSequential {
            guard node.inputs.count >= 2 else {
                throw LogicExecutionError.missingNodeInput
            }
            guard let outputSignal = node.outputs.first else {
                throw LogicExecutionError.missingOutput(node.id)
            }
            let outputWidth = try design.signalWidth(named: outputSignal)
            guard let dataSignal = sampledValues[node.inputs[0]] else {
                throw LogicExecutionError.unknownSignal(node.inputs[0])
            }
            let data = try dataSignal.broadcast(to: outputWidth)
            let clock = try scalarValue(sampledValues[node.inputs[1]], entity: node.id)
            let oldClock = previousClockValues[node.id] ?? .unknown
            let edge = node.parameters["edge"] ?? "positive"
            let isActiveEdge: Bool
            switch edge {
            case "positive":
                isActiveEdge = oldClock == .zero && clock == .one
            case "negative":
                isActiveEdge = oldClock == .one && clock == .zero
            default:
                throw LogicExecutionError.invalidDesign(
                    "sequential node \(node.id) has unsupported clock edge \(edge)"
                )
            }
            let asynchronousReset: (value: LogicValue, isActive: Bool, isUnknown: Bool)?
            if let resetSignal = node.parameters["resetSignal"], let resetEdge = node.parameters["resetEdge"] {
                let reset = try scalarValue(sampledValues[resetSignal], entity: node.id)
                let oldReset = previousResetValues[node.id] ?? .unknown
                let assertedValue: LogicValue
                switch resetEdge {
                case "positive": assertedValue = .one
                case "negative": assertedValue = .zero
                default:
                    throw LogicExecutionError.invalidDesign(
                        "sequential node \(node.id) has unsupported reset edge \(resetEdge)"
                    )
                }
                asynchronousReset = (
                    value: reset,
                    isActive: reset == assertedValue || (oldReset == .unknown && reset == assertedValue),
                    isUnknown: reset == .unknown || reset == .highImpedance
                )
            } else {
                asynchronousReset = nil
            }
            var nextValue: LogicVector
            if let existingValue = sampledValues[outputSignal] {
                nextValue = existingValue
            } else {
                nextValue = try LogicVector.unknown(width: outputWidth)
            }
            if let asynchronousReset, asynchronousReset.isActive {
                if let resetValue = node.parameters["resetValue"] {
                    nextValue = try LogicVector(string: resetValue).broadcast(to: outputWidth)
                } else {
                    nextValue = try LogicVector.zero(width: outputWidth)
                }
            } else if let asynchronousReset, asynchronousReset.isUnknown {
                nextValue = try LogicVector.unknown(width: outputWidth)
            } else if asynchronousReset == nil,
                      let resetSignal = node.parameters["resetSignal"],
                      isActiveEdge {
                let reset = try scalarValue(sampledValues[resetSignal], entity: node.id)
                switch reset {
                case .one:
                    nextValue = try LogicVector.zero(width: outputWidth)
                case .unknown, .highImpedance:
                    nextValue = try LogicVector.unknown(width: outputWidth)
                case .zero:
                    nextValue = data
                }
            } else if isActiveEdge {
                nextValue = data
            } else if clock == .unknown || clock == .highImpedance {
                let current: LogicVector
                if let existingValue = sampledValues[outputSignal] {
                    current = existingValue
                } else {
                    current = try LogicVector.unknown(width: outputWidth)
                }
                nextValue = current == data ? current : (try LogicVector.unknown(width: outputWidth))
            }
            pendingValues[outputSignal] = try nextValue.broadcast(to: outputWidth)
            pendingClockValues[node.id] = clock
            if let asynchronousReset {
                previousResetValues[node.id] = asynchronousReset.value
            }
        }
        values.merge(pendingValues) { _, new in new }
        previousClockValues.merge(pendingClockValues) { _, new in new }
    }

    private func evaluate(
        node: LogicNode,
        design: LogicDesignDocument,
        values: [String: LogicVector]
    ) throws -> LogicVector {
        let outputSignal = node.outputs.first ?? ""
        let outputWidth = try design.signalWidth(named: outputSignal)
        let rawInputs = try node.inputs.map { signal in
            guard let value = values[signal] else { throw LogicExecutionError.unknownSignal(signal) }
            return value
        }
        switch node.kind {
        case .caseEqual:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return try LogicVector.caseEqual(rawInputs[0], rawInputs[1])
        case .logicalAnd:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return LogicVector.logicalAnd(rawInputs[0], rawInputs[1])
        case .logicalOr:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return LogicVector.logicalOr(rawInputs[0], rawInputs[1])
        case .logicalNot:
            guard let input = rawInputs.first, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return LogicVector.logicalNot(input)
        case .add:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try arithmeticResult(
                node: node,
                lhs: rawInputs[0],
                rhs: rawInputs[1],
                width: outputWidth,
                operation: .add
            )
        case .subtract:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try arithmeticResult(
                node: node,
                lhs: rawInputs[0],
                rhs: rawInputs[1],
                width: outputWidth,
                operation: .subtract
            )
        case .multiply:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try arithmeticResult(
                node: node,
                lhs: rawInputs[0],
                rhs: rawInputs[1],
                width: outputWidth,
                operation: .multiply
            )
        case .shiftLeft:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try LogicVector.shiftedLeft(rawInputs[0], by: rawInputs[1], width: outputWidth)
        case .shiftRight:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            if node.parameters["signed"] == "true" {
                return try LogicVector.arithmeticShiftedRight(
                    rawInputs[0],
                    by: rawInputs[1],
                    width: outputWidth
                )
            }
            return try LogicVector.shiftedRight(rawInputs[0], by: rawInputs[1], width: outputWidth)
        case .concat:
            let result = try LogicVector.concatenated(rawInputs)
            guard result.width == outputWidth else {
                throw LogicExecutionError.vectorWidthMismatch(expected: outputWidth, actual: result.width)
            }
            return result
        case .slice:
            guard let source = rawInputs.first,
                  let sourceMSB = node.parameters["sourceMSB"].flatMap(Int.init),
                  let sourceLSB = node.parameters["sourceLSB"].flatMap(Int.init),
                  let selectionMSB = node.parameters["selectionMSB"].flatMap(Int.init),
                  let selectionLSB = node.parameters["selectionLSB"].flatMap(Int.init) else {
                throw LogicExecutionError.invalidDesign("slice node \(node.id) is missing range parameters")
            }
            let result = try source.sliced(
                sourceMSB: sourceMSB,
                sourceLSB: sourceLSB,
                selectionMSB: selectionMSB,
                selectionLSB: selectionLSB
            )
            guard result.width == outputWidth else {
                throw LogicExecutionError.vectorWidthMismatch(expected: outputWidth, actual: result.width)
            }
            return result
        default:
            break
        }
        let inputs = try rawInputs.map { value in
            try value.broadcast(to: outputWidth)
        }
        switch node.kind {
        case .and:
            return try LogicVector.and(inputs, width: outputWidth)
        case .or:
            return try LogicVector.or(inputs, width: outputWidth)
        case .xor:
            return try LogicVector.xor(inputs, width: outputWidth)
        case .nand:
            return try LogicVector.and(inputs, width: outputWidth).inverted()
        case .nor:
            return try LogicVector.or(inputs, width: outputWidth).inverted()
        case .xnor:
            return try LogicVector.xor(inputs, width: outputWidth).inverted()
        case .not:
            guard let input = inputs.first else { throw LogicExecutionError.missingNodeInput }
            return input.inverted()
        case .buffer:
            guard let input = inputs.first else { throw LogicExecutionError.missingNodeInput }
            return input
        case .constant:
            let text = node.parameters["value"] ?? String(repeating: "X", count: outputWidth)
            return try LogicVector(string: text).broadcast(to: outputWidth)
        case .mux:
            guard inputs.count >= 3 else { throw LogicExecutionError.missingNodeInput }
            let select = try scalarValue(inputs[0], entity: node.id)
            switch select {
            case .zero: return inputs[2]
            case .one: return inputs[1]
            case .unknown, .highImpedance: return try LogicVector.merge(inputs[1], inputs[2])
            }
        case .triState:
            guard inputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            let enable = try scalarValue(inputs[1], entity: node.id)
            switch enable {
            case .zero: return try LogicVector(bits: Array(repeating: .highImpedance, count: outputWidth))
            case .one: return inputs[0]
            case .unknown, .highImpedance: return try LogicVector.unknown(width: outputWidth)
            }
        case .dff:
            throw LogicExecutionError.invalidDesign("sequential node evaluated as combinational")
        default:
            throw LogicExecutionError.unsupportedNode(nodeID: node.id, kind: node.kind.rawValue)
        }
    }

    private func scalarValue(_ vector: LogicVector?, entity: String) throws -> LogicValue {
        guard let vector else { throw LogicExecutionError.unknownSignal(entity) }
        guard vector.width == 1 else {
            throw LogicExecutionError.invalidDesign("node \(entity) requires scalar control signals")
        }
        return vector[0]
    }

    private enum ArithmeticOperation {
        case add
        case subtract
        case multiply
    }

    private func arithmeticResult(
        node: LogicNode,
        lhs: LogicVector,
        rhs: LogicVector,
        width: Int,
        operation: ArithmeticOperation
    ) throws -> LogicVector {
        let isSigned = node.parameters["signed"] == "true"
        switch (operation, isSigned) {
        case (.add, false):
            return try LogicVector.added(lhs, rhs, width: width)
        case (.add, true):
            return try LogicVector.signedAdded(lhs, rhs, width: width)
        case (.subtract, false):
            return try LogicVector.subtracted(lhs, rhs, width: width)
        case (.subtract, true):
            return try LogicVector.signedSubtracted(lhs, rhs, width: width)
        case (.multiply, false):
            return try LogicVector.multiplied(lhs, rhs, width: width)
        case (.multiply, true):
            return try LogicVector.signedMultiplied(lhs, rhs, width: width)
        }
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
                identifier: "LogicSimulation",
                version: implementationVersion
            ),
            inputs: request.inputs,
            designRevision: request.design.designRevision ?? request.design.artifact.digest,
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
