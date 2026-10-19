import LogicKernelCore

public enum LogicEquivalenceInconclusive: Sendable {
    case interrupted(LogicKernelError)
    case initialStateReachabilityNotEstablished(LogicEquivalenceCounterexample)
    case eventDifferenceNotEstablished(LogicEquivalenceCounterexample)
}
