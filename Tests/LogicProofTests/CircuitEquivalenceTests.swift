import Testing
import LogicIR
import LogicKernelCore
import LogicProof
import LogicProofProbeSupport
import LogicSimulation

@Suite(.timeLimit(.minutes(1)))
struct CircuitEquivalenceTests {
    private typealias F = LogicEquivalenceContractProbe
    private typealias P = LogicProofContractProbe
    @Test func actualCellProofRefusesUnrealizedStartupMetadata() throws {
        var run = try P.context()
        for initial in [false, true] {
            let source = try F.state(initial: initial, context: &run)
            let mapped = try F.mappedState(initial: initial, context: &run)
            #expect(throws: LogicKernelError.self) {
                try F.problem(.bit(source), .mapped(mapped), inputs: 4, context: &run)
            }
            let omitted = try F.mappedState(context: &run)
            #expect(throws: LogicKernelError.invalidInput("Corresponding initial-state ranges differ")) {
                try F.problem(.bit(source), .mapped(omitted), inputs: 4, context: &run)
            }
        }
    }
    @Test func allBitOperationsProveAndRejectTheirInversionAgainstDirectTruth() throws {
        for operation in [BitOperation.constant(false), .constant(true), .buffer, .invert, .and, .or, .xor, .select] {
            var run = try P.context()
            let a = try F.bit(operation, context: &run); let b = try F.bit(operation, context: &run)
            let inverted = try F.bit(operation, inverted: true, context: &run)
            let equal = try F.problem(.bit(a), .bit(b), inputs: operation.operandCount, context: &run)
            guard case .equivalent(let proof) = try NativeLogicEquivalenceChecker().check(equal, context: &run) else { Issue.record("Equal bit operation was not proved"); continue }
            try proof.requireBinding(to: equal)
            let wrong = try F.problem(.bit(a), .bit(inverted), inputs: operation.operandCount, context: &run)
            guard case .different(let witness) = try NativeLogicEquivalenceChecker().check(wrong, context: &run) else { Issue.record("Inverted bit function was not rejected"); continue }
            try witness.requireBinding(to: wrong)
            #expect(witness.isAllowedInitialState && witness.hasConcreteEventDifference)
            #expect(witness.referenceEventObservation != nil && witness.candidateEventObservation != nil)
            for mask in 0..<(1 << operation.operandCount) {
                var inputs: [Bool] = []
                for bit in 0..<operation.operandCount { inputs.append(mask & (1 << bit) != 0) }
                let expected: Bool
                switch operation {
                case .constant(let value): expected = value
                case .buffer: expected = inputs[0]
                case .invert: expected = !inputs[0]
                case .and: expected = inputs[0] && inputs[1]
                case .or: expected = inputs[0] || inputs[1]
                case .xor: expected = inputs[0] != inputs[1]
                case .select: expected = inputs[0] ? inputs[1] : inputs[2]
                default: throw LogicKernelError.invalidInput("Invalid test operation")
                }
                let empty: [Bool] = []
                let result = try NativeLogicBinaryEvaluator().evaluate(.bit(a), inputs: inputs.span, currentState: empty.span, context: &run)
                result.withTables { outputs, _ in #expect(outputs[0] == expected) }
            }
        }
    }
    @Test func actualMappedFunctionsAndEnableLoweringUseCheckedEvidence() throws { try F.exercise() }
    @Test func asymmetricActualPinsAndExplicitInputPermutationAreProved() throws {
        var run = try P.context()
        let reference = try F.bit(invertedSecond: true, context: &run)
        let correct = try F.mapped(nand: false, asymmetric: true, context: &run)
        let swapped = try F.mapped(nand: false, asymmetric: true, swapInputs: true, context: &run)
        let equal = try F.problem(.bit(reference), .mapped(correct), inputs: 2, context: &run)
        guard case .equivalent = try NativeLogicEquivalenceChecker().check(equal, context: &run) else { Issue.record("Asymmetric actual function did not match"); return }
        let wrong = try F.problem(.bit(reference), .mapped(swapped), inputs: 2, context: &run)
        guard case .different = try NativeLogicEquivalenceChecker().check(wrong, context: &run) else { Issue.record("Swapped asymmetric pins escaped replay"); return }
        let pairs = try [LogicBitCorrespondence(reference: 0, candidate: 1), .init(reference: 1, candidate: 0)]
        let permuted = try LogicEquivalenceProblem(reference: .bit(reference), candidate: .mapped(swapped), inputs: pairs,
            outputs: F.correspondence(1), states: [], context: &run)
        guard case .equivalent = try NativeLogicEquivalenceChecker().check(permuted, context: &run) else { Issue.record("Explicit port permutation was not honored"); return }
    }
    @Test func resetSemanticsAndClosedLatchBehaviorCannotBeLost() throws {
        var run = try P.context()
        let ff = try F.state(context: &run)
        for candidate in [try F.state(synchronousReset: true, context: &run), try F.state(invertedReset: true, context: &run)] {
            let problem = try F.problem(.bit(ff), .bit(candidate), inputs: 4, context: &run)
            guard case .different(let witness) = try NativeLogicEquivalenceChecker().check(problem, context: &run) else { Issue.record("Wrong reset behavior escaped event replay"); continue }
            #expect(witness.hasConcreteEventDifference)
        }
        let latch = try F.state(latch: true, context: &run)
        let sameLatch = try F.state(latch: true, context: &run)
        let equal = try F.problem(.bit(latch), .bit(sameLatch), inputs: 4, context: &run)
        guard case .equivalent(let proof) = try NativeLogicEquivalenceChecker().check(equal, context: &run) else { Issue.record("Latch induction was not proved"); return }
        #expect(proof.kind == .statePreservingInduction)
        for gate in [false, true] {
            let inputs = [true, gate, true, true]; let initial = [false]
            let event = try NativeLogicBinaryEvaluator().replayInitialEvent(.bit(latch), inputs: inputs.span, initialState: initial.span, previousControl: false, context: &run)
            event.withStates { states in #expect(states[0] == gate) }
            event.observation.withTables { outputs, _ in #expect(outputs[0] == gate) }
        }
    }
    @Test func unreachableAndUnsettledRelationWitnessesNeverBecomeDifferent() throws {
        var run = try P.context()
        let holds = try F.holdingState(initial: false, clearsOnEdge: false, context: &run)
        let clears = try F.holdingState(initial: false, clearsOnEdge: true, context: &run)
        let problem = try F.problem(.bit(holds), .bit(clears), inputs: 1, context: &run)
        guard case .inconclusive(.initialStateReachabilityNotEstablished(let witness)) = try NativeLogicEquivalenceChecker().check(problem, context: &run) else { Issue.record("Unreachable state became a counterexample"); return }
        #expect(!witness.isAllowedInitialState && !witness.hasConcreteEventDifference)
        let latch = try F.state(latch: true, context: &run)
        let bypass = try F.state(latch: true, bypassLatch: true, context: &run)
        let transparent = try F.problem(.bit(latch), .bit(bypass), inputs: 4, context: &run)
        guard case .inconclusive(.eventDifferenceNotEstablished(let transient)) = try NativeLogicEquivalenceChecker().check(transparent, context: &run) else { Issue.record("Intermediate latch difference became a concrete counterexample"); return }
        #expect(!transient.hasConcreteEventDifference)
    }
    @Test func totalCorrespondenceInitialRangesAndReceiptBindingAreEnforced() throws {
        var run = try P.context()
        let a = try F.bit(context: &run); let b = try F.bit(context: &run)
        let outputs = try F.correspondence(1)
        #expect(throws: LogicKernelError.self) { try LogicEquivalenceProblem(reference: .bit(a), candidate: .bit(b), inputs: [], outputs: outputs, states: [], context: &run) }
        let duplicate = try [LogicBitCorrespondence(reference: 0, candidate: 0), .init(reference: 0, candidate: 1)]
        #expect(throws: LogicKernelError.self) { try LogicEquivalenceProblem(reference: .bit(a), candidate: .bit(b), inputs: duplicate, outputs: outputs, states: [], context: &run) }
        let ff = try F.state(initial: false, context: &run); let unknown = try F.state(context: &run)
        #expect(throws: LogicKernelError.self) { try F.problem(.bit(ff), .bit(unknown), inputs: 4, context: &run) }
        let falling = try F.state(risingEdge: false, context: &run)
        #expect(throws: LogicKernelError.self) { try F.problem(.bit(unknown), .bit(falling), inputs: 4, context: &run) }
        let first = try F.problem(.bit(a), .bit(b), inputs: 2, context: &run)
        let second = try F.problem(.bit(a), .bit(b), inputs: 2, context: &run)
        guard case .equivalent(let checked) = try NativeLogicEquivalenceChecker().check(first, context: &run) else { Issue.record("No checked equivalence"); return }
        #expect(throws: LogicKernelError.self) { try checked.requireBinding(to: second) }
    }
    private struct ForgedUNSAT: LogicSATSolving {
        func solve(_ formula: borrowing LogicCNFFormula, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATOutcome {
            let other = try P.formula([[]], variables: 0, context: &context)
            guard case .unsatisfiable(_, let statistics) = try NativeLogicSATSolver().solve(other, context: &context) else { throw .invalidModel("Invalid test contradiction") }
            return .unsatisfiable(try P.certificate([[]], formula: formula, context: &context), statistics)
        }
    }
    private struct WrongSATBinding: LogicSATSolving {
        func solve(_ formula: borrowing LogicCNFFormula, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATOutcome {
            try NativeLogicSATSolver().solve(P.formula([[1]], variables: 1, context: &context), context: &context)
        }
    }
    private struct WrongCheckedBinding: LogicProofChecking {
        func check(_ formula: borrowing LogicCNFFormula, certificate: borrowing LogicRUPCertificate, context: inout LogicKernelContext) throws(LogicKernelError) -> CheckedLogicProof {
            let other = try P.formula([[]], variables: 0, context: &context)
            return try NativeLogicRUPChecker().check(other, certificate: P.certificate([[]], formula: other, context: &context), context: &context)
        }
    }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private struct Expired: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .deadlineExceeded } }
    @Test func forgedAndWrongBoundEvidenceCannotBecomeEquivalence() throws {
        var run = try P.context()
        let and = try F.bit(context: &run); let nand = try F.mapped(nand: true, context: &run)
        let different = try F.problem(.bit(and), .mapped(nand), inputs: 2, context: &run)
        #expect(throws: LogicKernelError.self) { try NativeLogicEquivalenceChecker(solver: ForgedUNSAT()).check(different, context: &run) }
        #expect(throws: LogicKernelError.self) { try NativeLogicEquivalenceChecker(solver: WrongSATBinding()).check(different, context: &run) }
        let same = try F.problem(.bit(and), .bit(and), inputs: 2, context: &run)
        #expect(throws: LogicKernelError.self) { try NativeLogicEquivalenceChecker(checker: WrongCheckedBinding()).check(same, context: &run) }
    }
    @Test func resourceCancellationAndDeadlineRemainInconclusive() throws {
        var run = try P.context()
        let graph = try F.bit(context: &run)
        let problem = try F.problem(.bit(graph), .bit(graph), inputs: 2, context: &run)
        for control in [Cancelled() as any LogicRunControlling, Expired()] {
            var stopped = try P.context(control: control)
            guard case .inconclusive(.interrupted(let reason)) = try NativeLogicEquivalenceChecker().check(problem, context: &stopped) else { Issue.record("Interrupted proof became a verdict"); continue }
            #expect(reason == .cancelled || reason == .deadlineExceeded)
        }
        for resource in [LogicResource.cnfVariables, .cnfClauses, .proofBytes, .searchSteps, .managedStorageBytes, .workUnits, .outputBytes] {
            var maximums: [LogicResource: UInt64] = [:]
            for key in LogicResource.allCases { maximums[key] = 100_000_000 }
            maximums[resource] = 1
            var bounded = LogicKernelContext(limits: try .init(maximums: maximums), control: P.Control())
            guard case .inconclusive(.interrupted(let reason)) = try NativeLogicEquivalenceChecker().check(problem, context: &bounded) else { Issue.record("Resource exhaustion became a verdict"); continue }
            guard case .resourceLimit(let actual, _, _) = reason else { Issue.record("Wrong resource failure"); continue }
            #expect(actual == resource)
        }
    }
    @Test func nonstabilizingDerivedClockAndResetNeverPublishAnEvent() throws {
        var source = try P.context()
        var builder = try BitLogicBuilder(capacity: .init(nodes: 3, operands: 1, ports: 1, portBits: 1, states: 1), context: &source)
        let q = try builder.addNode(id: F.id(10), operation: .state(.init(0)), context: &source)
        let reset = try builder.addNode(id: F.id(11), operation: .invert, inputs: [q], context: &source)
        let zero = try builder.addNode(id: F.id(12), operation: .constant(false), context: &source)
        _ = try builder.addState(.init(id: F.id(50), next: zero, control: .flipFlop(clock: q, edge: .rising, enable: nil,
            reset: .init(signal: reset, activeHigh: true, value: true, kind: .asynchronous))), context: &source)
        try builder.addPort(id: F.id(40), direction: .output, bits: [q], context: &source)
        let graph = try builder.finish(context: &source)
        var maximums: [LogicResource: UInt64] = [:]
        for key in LogicResource.allCases { maximums[key] = 100_000_000 }
        maximums[.workUnits] = 100
        var bounded = LogicKernelContext(limits: try .init(maximums: maximums), control: P.Control())
        let inputs: [Bool] = []; let initial = [false]
        #expect(throws: LogicKernelError.self) { try NativeLogicBinaryEvaluator().replayInitialEvent(.bit(graph), inputs: inputs.span,
            initialState: initial.span, previousControl: false, context: &bounded) }
        #expect(bounded.usage[.managedStorageBytes] == 0)
        #expect(throws: LogicKernelError.self) { try NativeLogicBinaryEvaluator().evaluate(.bit(graph), inputs: inputs.span, currentState: inputs.span, context: &source) }
    }
    @Test func publishedTableMetadataRemainsAccountedAfterScratchRelease() throws {
        var source = try P.context()
        let formula = try P.formula([], variables: 0, context: &source)
        var solving = try P.context()
        guard case .satisfiable = try NativeLogicSATSolver().solve(formula, context: &solving) else { Issue.record("Empty CNF did not produce an assignment"); return }
        let assignmentStorage = UInt64(1 + MemoryLayout<[Int8]>.stride + MemoryLayout<LogicSATAssignment>.stride)
        #expect(solving.usage[.managedStorageBytes] == assignmentStorage)
        let graph = try F.bit(context: &source)
        var evaluating = try P.context()
        let inputs = [false, true]; let empty: [Bool] = []
        _ = try NativeLogicBinaryEvaluator().evaluate(.bit(graph), inputs: inputs.span, currentState: empty.span, context: &evaluating)
        let observationStorage = UInt64(3 + MemoryLayout<([Bool], [LogicBinaryStateAction])>.stride + MemoryLayout<LogicBinaryObservation>.stride)
        #expect(evaluating.usage[.managedStorageBytes] == observationStorage)
    }
}
