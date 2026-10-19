import LogicKernelCore
import LogicSimulation

public struct LogicEquivalenceCounterexample: Sendable {
    private final class Storage: Sendable {
        static var payloadByteCount: UInt64 {
            UInt64(MemoryLayout<(LogicEquivalenceProblem, [Bool], [Bool], [Bool], [Bool], LogicBinaryObservation, LogicBinaryObservation, LogicBinaryEventObservation?, LogicBinaryEventObservation?, [Bool]?, [Bool]?)>.stride)
        }
        let problem: LogicEquivalenceProblem
        let referenceInputs: [Bool]
        let candidateInputs: [Bool]
        let referenceState: [Bool]
        let candidateState: [Bool]
        let reference: LogicBinaryObservation
        let candidate: LogicBinaryObservation
        let referenceEvent: LogicBinaryEventObservation?
        let candidateEvent: LogicBinaryEventObservation?
        let referencePreviousControls: [Bool]?
        let candidatePreviousControls: [Bool]?
        init(problem: LogicEquivalenceProblem, referenceInputs: consuming [Bool], candidateInputs: consuming [Bool],
             referenceState: consuming [Bool], candidateState: consuming [Bool], reference: LogicBinaryObservation, candidate: LogicBinaryObservation,
             referenceEvent: LogicBinaryEventObservation?, candidateEvent: LogicBinaryEventObservation?,
             referencePreviousControls: consuming [Bool]?, candidatePreviousControls: consuming [Bool]?) {
            self.problem = problem; self.referenceInputs = referenceInputs; self.candidateInputs = candidateInputs
            self.referenceState = referenceState; self.candidateState = candidateState; self.reference = reference; self.candidate = candidate
            self.referenceEvent = referenceEvent; self.candidateEvent = candidateEvent
            self.referencePreviousControls = referencePreviousControls; self.candidatePreviousControls = candidatePreviousControls
        }
    }
    private let storage: Storage
    public let isAllowedInitialState: Bool
    public let hasConcreteEventDifference: Bool
    /// Common raw physical FF history when both confirmed history vectors are uniform; otherwise nil.
    public let previousControl: Bool?
    public var referenceObservation: LogicBinaryObservation { storage.reference }
    public var candidateObservation: LogicBinaryObservation { storage.candidate }
    public var referenceEventObservation: LogicBinaryEventObservation? { storage.referenceEvent }
    public var candidateEventObservation: LogicBinaryEventObservation? { storage.candidateEvent }
    private init(storage: Storage, allowed: Bool, eventDifference: Bool, previousControl: Bool?) {
        self.storage = storage; isAllowedInitialState = allowed; hasConcreteEventDifference = eventDifference; self.previousControl = previousControl
    }
    public func requireBinding(to problem: borrowing LogicEquivalenceProblem) throws(LogicKernelError) {
        guard storage.problem.storage === problem.storage else { throw .invalidInput("Counterexample belongs to another problem owner") }
    }
    public borrowing func withInputs<Result, Failure: Error>(
        _ body: (borrowing Span<Bool>, borrowing Span<Bool>, borrowing Span<Bool>, borrowing Span<Bool>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let li = owner.referenceInputs; let ri = owner.candidateInputs
        let ls = owner.referenceState; let rs = owner.candidateState
        defer { withExtendedLifetime(owner) {} }
        return try body(li.span, ri.span, ls.span, rs.span)
    }
    /// Borrows actual physical FF histories only for a confirmed event; nil does not invoke the closure.
    public borrowing func withEventControls<Result, Failure: Error>(
        _ body: (borrowing Span<Bool>, borrowing Span<Bool>) throws(Failure) -> Result
    ) throws(Failure) -> Result? {
        let owner = storage
        guard let left = owner.referencePreviousControls, let right = owner.candidatePreviousControls else { return nil }
        defer { withExtendedLifetime(owner) {} }
        return try body(left.span, right.span)
    }
    internal static func replay(_ problem: borrowing LogicEquivalenceProblem, miter: borrowing EquivalenceMiter,
                                assignment: borrowing LogicSATAssignment, context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try assignment.validate(miter.formula, context: &context)
        let statePayload = UInt64(problem.stateBitCount).multipliedReportingOverflow(by: 2)
        let count = UInt64(problem.inputBitCount).addingReportingOverflow(statePayload.partialValue)
        let payload = count.partialValue.multipliedReportingOverflow(by: 2)
        let total = payload.partialValue.addingReportingOverflow(Storage.payloadByteCount + UInt64(MemoryLayout<Self>.stride))
        guard !statePayload.overflow, !count.overflow, !payload.overflow, !total.overflow else { throw .invalidInput("Counterexample payload overflows") }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        try context.charge(.outputBytes, amount: total.partialValue)
        var li = [Bool](repeating: false, count: problem.inputBitCount); var ri = li
        var ls = [Bool](repeating: false, count: problem.stateBitCount); var rs = ls
        for pair in problem.storage.inputs {
            try context.charge(.workUnits)
            let literal = miter.inputVariables[pair.reference]
            let bit = try assignment.value(of: literal.variable) == literal.isPositive
            li[pair.reference] = bit; ri[pair.candidate] = bit
        }
        var allowed = true
        for pair in problem.storage.states {
            try context.charge(.workUnits)
            let literal = miter.stateVariables[pair.reference]
            let bit = try assignment.value(of: literal.variable) == literal.isPositive
            ls[pair.reference] = bit; rs[pair.candidate] = bit
            if let initial = problem.storage.referenceShape.initials[pair.reference], initial != bit { allowed = false }
        }
        // Replay always uses the concrete independent evaluator; injected search cannot replace it.
        let evaluator = NativeLogicBinaryEvaluator()
        let lhs = try evaluator.evaluate(problem.storage.reference, inputs: li.span, currentState: ls.span, context: &context)
        let rhs = try evaluator.evaluate(problem.storage.candidate, inputs: ri.span, currentState: rs.span, context: &context)
        var relationDifference = false; var eventDifference = false
        try lhs.withTables { leftOutputs, leftStates throws(LogicKernelError) in
            try rhs.withTables { rightOutputs, rightStates throws(LogicKernelError) in
                for pair in problem.storage.outputs {
                    try context.charge(.workUnits)
                    if leftOutputs[pair.reference] != rightOutputs[pair.candidate] { relationDifference = true; eventDifference = true }
                }
                for pair in problem.storage.states {
                    try context.charge(.workUnits)
                    let left = leftStates[pair.reference]; let right = rightStates[pair.candidate]
                    let leftControl = left.control != problem.storage.referenceShape.controlInversions[pair.reference]
                    let rightControl = right.control != problem.storage.candidateShape.controlInversions[pair.candidate]
                    let kind = problem.storage.referenceShape.kinds[pair.reference]
                    if leftControl != rightControl { relationDifference = true }
                    let a: Bool; let b: Bool
                    switch kind {
                    case .latch: a = left.sampled; b = right.sampled
                    case .flipFlop(let rising):
                        a = leftControl == rising ? left.sampled : left.asynchronous
                        b = rightControl == rising ? right.sampled : right.asynchronous
                    }
                    if a != b || left.asynchronous != right.asynchronous { relationDifference = true; eventDifference = true }
                }
            }
        }
        guard relationDifference else { throw .invalidModel("SAT witness did not reproduce a difference in the original circuit models") }
        // A relation witness is not a concrete counterexample until zero-delay events stabilize.
        eventDifference = false
        var referenceEvent: LogicBinaryEventObservation?
        var candidateEvent: LogicBinaryEventObservation?
        var previous: Bool?
        var referencePrevious: [Bool]?
        var candidatePrevious: [Bool]?
        var leftHistory = [Bool](repeating: false, count: problem.stateBitCount)
        var rightHistory = leftHistory
        if allowed {
            let count: Int
            if let kind = problem.storage.referenceShape.kinds.first, case .flipFlop = kind { count = 2 } else { count = 1 }
            for history in 0..<count {
                for pair in problem.storage.states {
                    try context.charge(.workUnits)
                    leftHistory[pair.reference] = (history == 1) != problem.storage.referenceShape.controlInversions[pair.reference]
                    rightHistory[pair.candidate] = (history == 1) != problem.storage.candidateShape.controlInversions[pair.candidate]
                }
                let left = try evaluator.replayInitialEvent(problem.storage.reference, inputs: li.span, initialState: ls.span, previousControls: leftHistory.span, context: &context)
                let right = try evaluator.replayInitialEvent(problem.storage.candidate, inputs: ri.span, initialState: rs.span, previousControls: rightHistory.span, context: &context)
                try left.observation.withTables { leftOutputs, _ throws(LogicKernelError) in
                    try right.observation.withTables { rightOutputs, _ throws(LogicKernelError) in
                        for pair in problem.storage.outputs { try context.charge(.workUnits); if leftOutputs[pair.reference] != rightOutputs[pair.candidate] { eventDifference = true } }
                    }
                }
                try left.withStates { leftStates throws(LogicKernelError) in
                    try right.withStates { rightStates throws(LogicKernelError) in
                        for pair in problem.storage.states { try context.charge(.workUnits); if leftStates[pair.reference] != rightStates[pair.candidate] { eventDifference = true } }
                    }
                }
                if eventDifference {
                    referenceEvent = left; candidateEvent = right
                    if count == 2 {
                        referencePrevious = leftHistory; candidatePrevious = rightHistory
                        if let first = leftHistory.first {
                            var common = true
                            for index in leftHistory.indices {
                                try context.charge(.workUnits)
                                if leftHistory[index] != first || rightHistory[index] != first { common = false }
                            }
                            if common { previous = first }
                        }
                    }
                    break
                }
            }
        }
        return .init(storage: .init(problem: copy problem, referenceInputs: li, candidateInputs: ri,
            referenceState: ls, candidateState: rs, reference: lhs, candidate: rhs, referenceEvent: referenceEvent, candidateEvent: candidateEvent,
            referencePreviousControls: referencePrevious, candidatePreviousControls: candidatePrevious),
            allowed: allowed, eventDifference: eventDifference, previousControl: previous)
    }
}
