import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicSimulation

/// Native exhaustive proof engine for the finite-state execution-graph profile.
///
/// The engine does not claim general SystemVerilog theorem proving. It proves
/// the declared finite transition relation exactly: every value assignment in
/// the selected two-state or four-state domain, every declared state, and every
/// clock context is explored. Limits and the complete traversal counts are
/// persisted in the report and certificate.
public struct NativeLogicUnboundedTemporalEquivalenceEngine:
    LogicUnboundedTemporalEquivalenceExecuting
{
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
        _ request: LogicUnboundedTemporalEquivalenceRequest
    ) async throws -> LogicUnboundedTemporalEquivalenceResult {
        let startedAt = Date()
        try request.validate()
        do {
            let requestDigest = try digest(of: request)
            let pair = try loadDesignPair(request: request)
            let outcome = try prove(
                request: request,
                pair: pair,
                startedAt: startedAt
            )
            return try materialize(
                request: request,
                requestDigest: requestDigest,
                pair: pair,
                outcome: outcome,
                startedAt: startedAt
            )
        } catch let error as LogicExecutionError {
            return try failureResult(request: request, error: error, startedAt: startedAt)
        }
    }

    private let solverID = "native-exhaustive-finite-state"

    private struct DesignPair: Sendable {
        let reference: LogicDesignDocument
        let implementation: LogicDesignDocument
        let outputSignals: [String]
        let stateSignals: [String]
        let inputSignals: [String]
        let clockSignal: String?
    }

    private struct ProofOutcome: Sendable {
        let status: LogicUnboundedTemporalEquivalenceStatus
        let exploredStateCount: Int
        let exploredTransitionCount: Int
        let difference: LogicUnboundedTemporalEquivalenceDifference?
    }

    private func loadDesignPair(
        request: LogicUnboundedTemporalEquivalenceRequest
    ) throws -> DesignPair {
        let reference = try decodeDesign(
            artifact: request.referenceDesign.artifact,
            label: "reference"
        )
        let implementation = try decodeDesign(
            artifact: request.implementationDesign.artifact,
            label: "implementation"
        )
        try validatePair(
            request: request,
            reference: reference,
            implementation: implementation
        )

        let referenceStateSignals = try stateSignals(in: reference)
        let implementationStateSignals = try stateSignals(in: implementation)
        guard referenceStateSignals == implementationStateSignals else {
            throw LogicExecutionError.missingPrerequisite(
                "reference and implementation require a common sequential state interface"
            )
        }
        for signal in referenceStateSignals {
            let referenceWidth = try reference.signalWidth(named: signal)
            let implementationWidth = try implementation.signalWidth(named: signal)
            guard referenceWidth == implementationWidth else {
                throw LogicExecutionError.missingPrerequisite(
                    "state signal \(signal) has different widths between designs"
                )
            }
        }

        let sequential = !referenceStateSignals.isEmpty
        let clock = try clockSignal(
            request: request,
            reference: reference,
            implementation: implementation,
            sequential: sequential
        )
        let referenceInputs = inputSignals(in: reference)
        let implementationInputs = inputSignals(in: implementation)
        guard referenceInputs == implementationInputs else {
            throw LogicExecutionError.missingPrerequisite(
                "reference and implementation require a common input interface"
            )
        }
        let nonClockInputs = referenceInputs.filter { $0 != clock }
        let outputSignals = try requestedOutputSignals(
            request: request,
            reference: reference,
            implementation: implementation
        )
        return DesignPair(
            reference: reference,
            implementation: implementation,
            outputSignals: outputSignals,
            stateSignals: referenceStateSignals,
            inputSignals: nonClockInputs,
            clockSignal: clock
        )
    }

    private func decodeDesign(
        artifact: ArtifactReference,
        label: String
    ) throws -> LogicDesignDocument {
        let data = try artifactStore.read(artifact)
        do {
            let design = try JSONDecoder().decode(LogicDesignDocument.self, from: data)
            try design.validate()
            try design.validateNativeExecutionTopology()
            if let unsupported = design.nodes.first(where: { !$0.kind.isSupported }) {
                throw LogicExecutionError.unsupportedNode(
                    nodeID: unsupported.id,
                    kind: unsupported.kind.rawValue
                )
            }
            return design
        } catch let error as LogicExecutionError {
            throw error
        } catch {
            throw LogicExecutionError.invalidArtifact(
                "unbounded equivalence \(label) design JSON could not be decoded: \(error.localizedDescription)"
            )
        }
    }

    private func validatePair(
        request: LogicUnboundedTemporalEquivalenceRequest,
        reference: LogicDesignDocument,
        implementation: LogicDesignDocument
    ) throws {
        guard reference.topDesignName == request.referenceDesign.topDesignName,
              implementation.topDesignName == request.implementationDesign.topDesignName,
              reference.topDesignName == implementation.topDesignName else {
            throw LogicExecutionError.invalidDesign(
                "unbounded equivalence design top names do not match"
            )
        }
        guard reference.ports == implementation.ports else {
            throw LogicExecutionError.missingPrerequisite(
                "reference and implementation require the same port interface"
            )
        }
    }

    private func stateSignals(in design: LogicDesignDocument) throws -> [String] {
        var signals: [String] = []
        for node in design.nodes where node.kind.isSequential {
            guard node.outputs.count == 1, let signal = node.outputs.first else {
                throw LogicExecutionError.missingOutput(node.id)
            }
            signals.append(signal)
        }
        guard Set(signals).count == signals.count else {
            throw LogicExecutionError.invalidDesign("sequential state has duplicate output signals")
        }
        return signals.sorted()
    }

    private func inputSignals(in design: LogicDesignDocument) -> [String] {
        design.ports
            .filter { $0.direction == .input }
            .map(\.name)
            .sorted()
    }

    private func clockSignal(
        request: LogicUnboundedTemporalEquivalenceRequest,
        reference: LogicDesignDocument,
        implementation: LogicDesignDocument,
        sequential: Bool
    ) throws -> String? {
        guard sequential else {
            guard request.clockSignal == nil else {
                throw LogicExecutionError.missingPrerequisite(
                    "a clock signal is only valid for sequential designs"
                )
            }
            return nil
        }
        let referenceLatches = reference.nodes.filter { $0.kind == .latch }
        let implementationLatches = implementation.nodes.filter { $0.kind == .latch }
        guard referenceLatches.count == implementationLatches.count else {
            throw LogicExecutionError.missingPrerequisite(
                "reference and implementation require the same level-sensitive state interface"
            )
        }
        for (referenceLatch, implementationLatch) in zip(referenceLatches, implementationLatches) {
            guard referenceLatch.inputs.count >= 2,
                  implementationLatch.inputs.count >= 2,
                  referenceLatch.inputs[1] == implementationLatch.inputs[1] else {
                throw LogicExecutionError.missingPrerequisite(
                    "reference and implementation require a common latch enable interface"
                )
            }
            let referencePort = reference.ports.first { $0.name == referenceLatch.inputs[1] }
            let implementationPort = implementation.ports.first { $0.name == implementationLatch.inputs[1] }
            guard referencePort?.direction == .input,
                  implementationPort?.direction == .input,
                  referencePort?.width == 1,
                  implementationPort?.width == 1 else {
                throw LogicExecutionError.missingPrerequisite(
                    "latch enable signals must be scalar input ports"
                )
            }
        }
        let referenceEdgeNodes = reference.nodes.filter { $0.kind == .dff }
        let implementationEdgeNodes = implementation.nodes.filter { $0.kind == .dff }
        guard referenceEdgeNodes.count == implementationEdgeNodes.count else {
            throw LogicExecutionError.missingPrerequisite(
                "reference and implementation require the same edge-triggered state interface"
            )
        }
        guard !referenceEdgeNodes.isEmpty else {
            guard request.clockSignal == nil else {
                throw LogicExecutionError.missingPrerequisite(
                    "a clock signal is not valid for latch-only designs"
                )
            }
            return nil
        }
        let referenceClocks = try Set(referenceEdgeNodes.map { node in
            guard node.inputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return node.inputs[1]
        })
        let implementationClocks = try Set(implementationEdgeNodes.map { node in
            guard node.inputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return node.inputs[1]
        })
        guard referenceClocks.count == 1,
              referenceClocks == implementationClocks,
              let inferred = referenceClocks.first else {
            throw LogicExecutionError.missingPrerequisite(
                "all sequential nodes require one common clock signal"
            )
        }
        let selected = request.clockSignal ?? inferred
        guard selected == inferred else {
            throw LogicExecutionError.missingPrerequisite(
                "requested clock signal does not match the execution graph"
            )
        }
        let referencePort = reference.ports.first { $0.name == selected }
        let implementationPort = implementation.ports.first { $0.name == selected }
        guard referencePort?.direction == .input,
              implementationPort?.direction == .input,
              referencePort?.width == 1,
              implementationPort?.width == 1 else {
            throw LogicExecutionError.missingPrerequisite(
                "the common clock signal must be a scalar input port"
            )
        }
        return selected
    }

    private func requestedOutputSignals(
        request: LogicUnboundedTemporalEquivalenceRequest,
        reference: LogicDesignDocument,
        implementation: LogicDesignDocument
    ) throws -> [String] {
        let requested = request.outputSignals.isEmpty
            ? reference.ports.filter { $0.direction == .output }.map(\.name).sorted()
            : request.outputSignals
        guard !requested.isEmpty else {
            throw LogicExecutionError.missingPrerequisite(
                "unbounded temporal equivalence requires an output signal"
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

    private func prove(
        request: LogicUnboundedTemporalEquivalenceRequest,
        pair: DesignPair,
        startedAt: Date
    ) throws -> ProofOutcome {
        try checkDeadline(startedAt, timeoutNanoseconds: request.timeoutNanoseconds)
        let countCap = max(request.stateSpaceLimit, request.transitionLimit)
        let stateCount = try assignmentCount(
            signals: pair.stateSignals,
            design: pair.reference,
            domain: request.valueDomain,
            cap: countCap
        )
        guard stateCount <= request.stateSpaceLimit else {
            throw LogicExecutionError.missingPrerequisite(
                "state space " + String(stateCount) + " exceeds limit " + String(request.stateSpaceLimit)
            )
        }
        guard stateCount <= request.transitionLimit else {
            throw LogicExecutionError.missingPrerequisite(
                "transition space exceeds limit " + String(request.transitionLimit)
            )
        }
        let inputCount = try assignmentCount(
            signals: pair.inputSignals,
            design: pair.reference,
            domain: request.valueDomain,
            cap: request.transitionLimit
        )
        let clockValues = request.valueDomain.values
        let transitionCount: Int
        if pair.clockSignal == nil {
            transitionCount = try product([stateCount, inputCount], label: "combinational transition space")
        } else {
            transitionCount = try product(
                [stateCount, inputCount, clockValues.count, clockValues.count],
                label: "sequential transition space"
            )
        }
        guard transitionCount <= request.transitionLimit else {
            throw LogicExecutionError.missingPrerequisite(
                "transition space " + String(transitionCount) + " exceeds limit " + String(request.transitionLimit)
            )
        }
        let stateAssignments = try enumerateAssignments(
            signals: pair.stateSignals,
            design: pair.reference,
            domain: request.valueDomain,
            startedAt: startedAt,
            timeoutNanoseconds: request.timeoutNanoseconds
        )
        let inputAssignments = try enumerateAssignments(
            signals: pair.inputSignals,
            design: pair.reference,
            domain: request.valueDomain,
            startedAt: startedAt,
            timeoutNanoseconds: request.timeoutNanoseconds
        )

        let evaluator = LogicExecutionGraphEvaluator()
        var exploredStates = 0
        var exploredTransitions = 0
        for state in stateAssignments {
            try checkDeadline(startedAt, timeoutNanoseconds: request.timeoutNanoseconds)
            exploredStates += 1
            for input in inputAssignments {
                if let clockSignal = pair.clockSignal {
                    for previousClock in clockValues {
                        for currentClock in clockValues {
                            try checkDeadline(startedAt, timeoutNanoseconds: request.timeoutNanoseconds)
                            exploredTransitions += 1
                            let difference = try compareTransition(
                                state: state,
                                input: input,
                                clockSignal: clockSignal,
                                previousClock: previousClock,
                                currentClock: currentClock,
                                pair: pair,
                                evaluator: evaluator
                            )
                            if let difference {
                                return ProofOutcome(
                                    status: .counterexample,
                                    exploredStateCount: exploredStates,
                                    exploredTransitionCount: exploredTransitions,
                                    difference: difference
                                )
                            }
                        }
                    }
                } else if !pair.stateSignals.isEmpty {
                    try checkDeadline(startedAt, timeoutNanoseconds: request.timeoutNanoseconds)
                    exploredTransitions += 1
                    let difference = try compareLevelSensitive(
                        state: state,
                        input: input,
                        pair: pair,
                        evaluator: evaluator
                    )
                    if let difference {
                        return ProofOutcome(
                            status: .counterexample,
                            exploredStateCount: exploredStates,
                            exploredTransitionCount: exploredTransitions,
                            difference: difference
                        )
                    }
                } else {
                    try checkDeadline(startedAt, timeoutNanoseconds: request.timeoutNanoseconds)
                    exploredTransitions += 1
                    let difference = try compareCombinational(
                        state: state,
                        input: input,
                        pair: pair,
                        evaluator: evaluator
                    )
                    if let difference {
                        return ProofOutcome(
                            status: .counterexample,
                            exploredStateCount: exploredStates,
                            exploredTransitionCount: exploredTransitions,
                            difference: difference
                        )
                    }
                }
            }
        }
        return ProofOutcome(
            status: .proved,
            exploredStateCount: exploredStates,
            exploredTransitionCount: exploredTransitions,
            difference: nil
        )
    }

    private func compareCombinational(
        state: [String: LogicVector],
        input: [String: LogicVector],
        pair: DesignPair,
        evaluator: LogicExecutionGraphEvaluator
    ) throws -> LogicUnboundedTemporalEquivalenceDifference? {
        var referenceValues = try initialValues(for: pair.reference)
        var implementationValues = try initialValues(for: pair.implementation)
        for (signal, value) in state.merging(input, uniquingKeysWith: { _, new in new }) {
            referenceValues[signal] = value
            implementationValues[signal] = value
        }
        try evaluator.settleCombinational(design: pair.reference, values: &referenceValues)
        try evaluator.settleCombinational(design: pair.implementation, values: &implementationValues)
        let referenceOutputs = try values(for: pair.outputSignals, in: referenceValues)
        let implementationOutputs = try values(for: pair.outputSignals, in: implementationValues)
        guard referenceOutputs != implementationOutputs else { return nil }
        return LogicUnboundedTemporalEquivalenceDifference(
            state: state,
            inputs: input,
            previousClock: nil,
            currentClock: nil,
            referenceOutputs: referenceOutputs,
            implementationOutputs: implementationOutputs
        )
    }

    private func compareLevelSensitive(
        state: [String: LogicVector],
        input: [String: LogicVector],
        pair: DesignPair,
        evaluator: LogicExecutionGraphEvaluator
    ) throws -> LogicUnboundedTemporalEquivalenceDifference? {
        var referenceValues = try initialValues(for: pair.reference)
        var implementationValues = try initialValues(for: pair.implementation)
        for (signal, value) in state.merging(input, uniquingKeysWith: { _, new in new }) {
            referenceValues[signal] = value
            implementationValues[signal] = value
        }
        try evaluator.settleCombinational(design: pair.reference, values: &referenceValues)
        try evaluator.settleCombinational(design: pair.implementation, values: &implementationValues)
        let referenceOutputs = try values(for: pair.outputSignals, in: referenceValues)
        let implementationOutputs = try values(for: pair.outputSignals, in: implementationValues)
        var referencePreviousClocks: [String: LogicValue] = [:]
        var implementationPreviousClocks: [String: LogicValue] = [:]
        var referencePreviousResets: [String: LogicValue] = [:]
        var implementationPreviousResets: [String: LogicValue] = [:]
        try evaluator.updateSequential(
            design: pair.reference,
            values: &referenceValues,
            previousClockValues: &referencePreviousClocks,
            previousResetValues: &referencePreviousResets
        )
        try evaluator.updateSequential(
            design: pair.implementation,
            values: &implementationValues,
            previousClockValues: &implementationPreviousClocks,
            previousResetValues: &implementationPreviousResets
        )
        try evaluator.settleCombinational(design: pair.reference, values: &referenceValues)
        try evaluator.settleCombinational(design: pair.implementation, values: &implementationValues)
        let referenceNextState = try values(for: pair.stateSignals, in: referenceValues)
        let implementationNextState = try values(for: pair.stateSignals, in: implementationValues)
        guard referenceOutputs == implementationOutputs,
              referenceNextState == implementationNextState else {
            return LogicUnboundedTemporalEquivalenceDifference(
                state: state,
                inputs: input,
                previousClock: nil,
                currentClock: nil,
                referenceOutputs: referenceOutputs,
                implementationOutputs: implementationOutputs,
                referenceNextState: referenceNextState,
                implementationNextState: implementationNextState
            )
        }
        return nil
    }

    private func compareTransition(
        state: [String: LogicVector],
        input: [String: LogicVector],
        clockSignal: String,
        previousClock: LogicValue,
        currentClock: LogicValue,
        pair: DesignPair,
        evaluator: LogicExecutionGraphEvaluator
    ) throws -> LogicUnboundedTemporalEquivalenceDifference? {
        var referenceValues = try initialValues(for: pair.reference)
        var implementationValues = try initialValues(for: pair.implementation)
        var completeInput = input
        completeInput[clockSignal] = LogicVector(currentClock)
        for (signal, value) in completeInput {
            referenceValues[signal] = value
            implementationValues[signal] = value
        }
        try evaluator.settleCombinational(design: pair.reference, values: &referenceValues)
        try evaluator.settleCombinational(design: pair.implementation, values: &implementationValues)
        let referenceOutputs = try values(for: pair.outputSignals, in: referenceValues)
        let implementationOutputs = try values(for: pair.outputSignals, in: implementationValues)

        var referencePreviousClocks = Dictionary(
            uniqueKeysWithValues: pair.reference.nodes
                .filter { $0.kind.isSequential }
                .map { ($0.id, previousClock) }
        )
        var implementationPreviousClocks = Dictionary(
            uniqueKeysWithValues: pair.implementation.nodes
                .filter { $0.kind.isSequential }
                .map { ($0.id, previousClock) }
        )
        var referencePreviousResets: [String: LogicValue] = [:]
        var implementationPreviousResets: [String: LogicValue] = [:]
        try evaluator.updateSequential(
            design: pair.reference,
            values: &referenceValues,
            previousClockValues: &referencePreviousClocks,
            previousResetValues: &referencePreviousResets
        )
        try evaluator.updateSequential(
            design: pair.implementation,
            values: &implementationValues,
            previousClockValues: &implementationPreviousClocks,
            previousResetValues: &implementationPreviousResets
        )
        try evaluator.settleCombinational(design: pair.reference, values: &referenceValues)
        try evaluator.settleCombinational(design: pair.implementation, values: &implementationValues)
        let referenceNextState = try values(for: pair.stateSignals, in: referenceValues)
        let implementationNextState = try values(for: pair.stateSignals, in: implementationValues)
        guard referenceOutputs == implementationOutputs,
              referenceNextState == implementationNextState else {
            return LogicUnboundedTemporalEquivalenceDifference(
                state: state,
                inputs: input,
                previousClock: previousClock,
                currentClock: currentClock,
                referenceOutputs: referenceOutputs,
                implementationOutputs: implementationOutputs,
                referenceNextState: referenceNextState,
                implementationNextState: implementationNextState
            )
        }
        return nil
    }

    private func initialValues(
        for design: LogicDesignDocument
    ) throws -> [String: LogicVector] {
        var values: [String: LogicVector] = [:]
        for signal in design.signals {
            if let initialValue = signal.initialValue {
                values[signal.name] = initialValue
            } else {
                values[signal.name] = try LogicVector.unknown(width: signal.width)
            }
        }
        return values
    }

    private func values(
        for signals: [String],
        in values: [String: LogicVector]
    ) throws -> [String: LogicVector] {
        var result: [String: LogicVector] = [:]
        for signal in signals {
            guard let value = values[signal] else {
                throw LogicExecutionError.unknownSignal(signal)
            }
            result[signal] = value
        }
        return result
    }

    private func enumerateAssignments(
        signals: [String],
        design: LogicDesignDocument,
        domain: LogicUnboundedTemporalEquivalenceDomain,
        startedAt: Date,
        timeoutNanoseconds: UInt64
    ) throws -> [[String: LogicVector]] {
        guard !signals.isEmpty else { return [[:]] }
        let vectors = try signals.map { signal in
            let width = try design.signalWidth(named: signal)
            return try enumerateVectors(
                width: width,
                domain: domain,
                startedAt: startedAt,
                timeoutNanoseconds: timeoutNanoseconds
            )
        }
        var assignments: [[String: LogicVector]] = []
        func append(_ index: Int, _ current: [String: LogicVector]) throws {
            try checkDeadline(startedAt, timeoutNanoseconds: timeoutNanoseconds)
            if index == signals.count {
                assignments.append(current)
                return
            }
            for vector in vectors[index] {
                var next = current
                next[signals[index]] = vector
                try append(index + 1, next)
            }
        }
        try append(0, [:])
        return assignments
    }

    private func assignmentCount(
        signals: [String],
        design: LogicDesignDocument,
        domain: LogicUnboundedTemporalEquivalenceDomain,
        cap: Int
    ) throws -> Int {
        guard cap > 0 else {
            throw LogicExecutionError.missingPrerequisite("assignment count cap must be positive")
        }
        var count = 1
        for signal in signals {
            let width = try design.signalWidth(named: signal)
            guard width > 0 else {
                throw LogicExecutionError.invalidSignalWidth(width)
            }
            for _ in 0..<width {
                guard count <= cap / domain.values.count else {
                    return cap == Int.max ? Int.max : cap + 1
                }
                count *= domain.values.count
            }
        }
        return count
    }

    private func enumerateVectors(
        width: Int,
        domain: LogicUnboundedTemporalEquivalenceDomain,
        startedAt: Date,
        timeoutNanoseconds: UInt64
    ) throws -> [LogicVector] {
        guard width > 0 else { throw LogicExecutionError.invalidSignalWidth(width) }
        var vectors: [LogicVector] = []
        func append(_ index: Int, _ bits: [LogicValue]) throws {
            try checkDeadline(startedAt, timeoutNanoseconds: timeoutNanoseconds)
            if index == width {
                vectors.append(try LogicVector(bits: bits))
                return
            }
            for value in domain.values {
                try append(index + 1, bits + [value])
            }
        }
        try append(0, [])
        return vectors
    }

    private func product(_ values: [Int], label: String) throws -> Int {
        var result = 1
        for value in values {
            guard value >= 0, result <= Int.max / max(1, value) else {
                throw LogicExecutionError.missingPrerequisite("\(label) exceeds native integer capacity")
            }
            result *= value
        }
        return result
    }

    private func checkDeadline(_ startedAt: Date, timeoutNanoseconds: UInt64) throws {
        if Task.isCancelled {
            throw LogicExecutionError.cancelled
        }
        let elapsedNanoseconds = Date().timeIntervalSince(startedAt) * 1_000_000_000
        if elapsedNanoseconds > Double(timeoutNanoseconds) {
            throw LogicExecutionError.timedOut("declared proof timeout was exceeded")
        }
    }

    private func materialize(
        request: LogicUnboundedTemporalEquivalenceRequest,
        requestDigest: String,
        pair: DesignPair,
        outcome: ProofOutcome,
        startedAt: Date
    ) throws -> LogicUnboundedTemporalEquivalenceResult {
        let report = LogicUnboundedTemporalEquivalenceReport(
            runID: request.runID,
            requestDigest: requestDigest,
            referenceDesignDigest: request.referenceDesign.designDigest,
            implementationDesignDigest: request.implementationDesign.designDigest,
            valueDomain: request.valueDomain,
            outputSignals: pair.outputSignals,
            stateSignals: pair.stateSignals,
            inputSignals: pair.inputSignals,
            stateSpaceLimit: request.stateSpaceLimit,
            transitionLimit: request.transitionLimit,
            exploredStateCount: outcome.exploredStateCount,
            exploredTransitionCount: outcome.exploredTransitionCount,
            solverID: solverID,
            solverVersion: implementationVersion,
            status: outcome.status,
            differences: outcome.difference.map { [$0] } ?? []
        )
        try report.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportData = try encoder.encode(report)
        let reportDigest = try SHA256ContentDigester()
            .digest(data: reportData, using: .sha256)
            .hexadecimalValue
        let reportReference = try artifactStore.write(
            reportData,
            fileName: "logic-unbounded-temporal-equivalence-report.json",
            outputDirectory: request.artifactDirectory,
            runID: request.runID,
            artifactID: "logic-unbounded-temporal-equivalence-report",
            kind: .report,
            format: .json
        )
        var producedArtifacts = [reportReference]
        let certificateReference: ArtifactReference?
        if outcome.status == .proved {
            let certificate = LogicUnboundedTemporalEquivalenceCertificate(
                requestDigest: requestDigest,
                reportDigest: reportDigest,
                solverID: solverID,
                solverVersion: implementationVersion,
                proofScope: report.proofScope,
                valueDomain: request.valueDomain,
                exploredStateCount: outcome.exploredStateCount,
                exploredTransitionCount: outcome.exploredTransitionCount,
                complete: true,
                status: .proved
            )
            try certificate.validate()
            let certificateData = try encoder.encode(certificate)
            certificateReference = try artifactStore.write(
                certificateData,
                fileName: "logic-unbounded-temporal-equivalence-certificate.json",
                outputDirectory: request.artifactDirectory,
                runID: request.runID,
                artifactID: "logic-unbounded-temporal-equivalence-certificate",
                kind: .report,
                format: .json
            )
            if let certificateReference {
                producedArtifacts.append(certificateReference)
            }
        } else {
            certificateReference = nil
        }
        let counterexampleReference: ArtifactReference?
        if outcome.status == .counterexample {
            counterexampleReference = try artifactStore.write(
                reportData,
                fileName: "logic-unbounded-temporal-counterexample.json",
                outputDirectory: request.artifactDirectory,
                runID: request.runID,
                artifactID: "logic-unbounded-temporal-counterexample",
                kind: .report,
                format: .json
            )
            if let counterexampleReference {
                producedArtifacts.append(counterexampleReference)
            }
        } else {
            counterexampleReference = nil
        }
        let producer = try producerIdentity()
        let artifacts = producedArtifacts
        let diagnostics = try diagnostics(
            for: outcome.status,
            exploredTransitionCount: outcome.exploredTransitionCount
        )
        let payload = LogicUnboundedTemporalEquivalencePayload(
            proofStatus: outcome.status,
            exploredStateCount: outcome.exploredStateCount,
            exploredTransitionCount: outcome.exploredTransitionCount,
            outputSignals: pair.outputSignals,
            stateSignals: pair.stateSignals,
            inputSignals: pair.inputSignals,
            equivalenceReport: reportReference,
            proofCertificate: certificateReference,
            counterexample: counterexampleReference
        )
        return try makeResult(
            request: request,
            status: outcome.status == .proved ? .completed : .failed,
            payload: payload,
            artifacts: artifacts,
            diagnostics: diagnostics,
            producer: producer,
            startedAt: startedAt
        )
    }

    private func failureResult(
        request: LogicUnboundedTemporalEquivalenceRequest,
        error: LogicExecutionError,
        startedAt: Date
    ) throws -> LogicUnboundedTemporalEquivalenceResult {
        let producer = try producerIdentity()
        let designDiagnostic: DesignDiagnostic
        if case .timedOut = error {
            designDiagnostic = DesignDiagnostic(
                severity: .warning,
                code: "LOGIC_UNBOUNDED_TEMPORAL_EQUIVALENCE_TIMEOUT",
                message: error.localizedDescription,
                suggestedActions: ["increase_timeout_budget", "reduce_declared_state_or_input_space"]
            )
        } else {
            designDiagnostic = LogicDiagnosticFactory.make(for: error)
        }
        let diagnostic = designDiagnostic
        let executionStatus: LogicIR.LogicExecutionStatus
        let proofStatus: LogicUnboundedTemporalEquivalenceStatus
        switch error {
        case .timedOut:
            executionStatus = .blocked
            proofStatus = .timeout
        case .unsupportedNode, .missingPrerequisite, .unsupportedWaveform, .cancelled:
            executionStatus = error == .cancelled ? .cancelled : .blocked
            proofStatus = .blocked
        default:
            executionStatus = .failed
            proofStatus = .blocked
        }
        let payload = LogicUnboundedTemporalEquivalencePayload(proofStatus: proofStatus)
        return try makeResult(
            request: request,
            status: executionStatus,
            payload: payload,
            artifacts: [],
            diagnostics: [diagnostic],
            producer: producer,
            startedAt: startedAt
        )
    }

    private func diagnostics(
        for status: LogicUnboundedTemporalEquivalenceStatus,
        exploredTransitionCount: Int
    ) throws -> [DesignDiagnostic] {
        let designDiagnostic: DesignDiagnostic
        switch status {
        case .proved:
            designDiagnostic = DesignDiagnostic(
                severity: .information,
                code: "LOGIC_UNBOUNDED_TEMPORAL_EQUIVALENCE_PROVED",
                message: "The complete finite transition relation was exhausted and no mismatch was found.",
                suggestedActions: ["retain_unbounded_equivalence_certificate", "proceed_to_human_review"]
            )
        case .counterexample:
            designDiagnostic = DesignDiagnostic(
                severity: .error,
                code: "LOGIC_UNBOUNDED_TEMPORAL_COUNTEREXAMPLE",
                message: "The exhaustive finite transition relation contains a mismatch.",
                suggestedActions: ["inspect_unbounded_counterexample", "repair_implementation"]
            )
        case .blocked:
            designDiagnostic = DesignDiagnostic(
                severity: .warning,
                code: "LOGIC_UNBOUNDED_TEMPORAL_BLOCKED",
                message: "The declared finite transition relation could not be exhausted.",
                suggestedActions: ["increase_proof_limits", "provide_supported_execution_graph"]
            )
        case .timeout:
            designDiagnostic = DesignDiagnostic(
                severity: .warning,
                code: "LOGIC_UNBOUNDED_TEMPORAL_TIMEOUT",
                message: "The exhaustive proof exceeded its declared timeout.",
                suggestedActions: ["increase_timeout_budget", "reduce_declared_state_or_input_space"]
            )
        }
        let diagnostic = designDiagnostic
        if status == .proved, exploredTransitionCount == 0 {
            throw LogicExecutionError.invalidArtifact("a proof must explore at least one transition")
        }
        return [diagnostic]
    }

    private func makeResult(
        request: LogicUnboundedTemporalEquivalenceRequest,
        status: LogicIR.LogicExecutionStatus,
        payload: LogicUnboundedTemporalEquivalencePayload,
        artifacts: [ArtifactReference],
        diagnostics: [DesignDiagnostic],
        producer: ProducerIdentity,
        startedAt: Date
    ) throws -> LogicUnboundedTemporalEquivalenceResult {
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            startedAt: startedAt,
            completedAt: Date()
        )
        return LogicUnboundedTemporalEquivalenceResult(
            runID: request.runID,
            status: status,
            payload: payload,
            artifacts: artifacts,
            diagnostics: diagnostics,
            provenance: provenance
        )
    }

    private func producerIdentity() throws -> ProducerIdentity {
        try ProducerIdentity(
            kind: .engine,
            identifier: "LogicUnboundedTemporalEquivalence",
            version: implementationVersion,
            build: solverID
        )
    }

    private func digest(
        of request: LogicUnboundedTemporalEquivalenceRequest
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try SHA256ContentDigester()
            .digest(data: try encoder.encode(request), using: .sha256)
            .hexadecimalValue
    }
}
