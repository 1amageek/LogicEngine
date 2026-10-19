public enum LogicEquivalenceVerdict: Sendable {
    case equivalent(CheckedLogicEquivalence)
    case different(LogicEquivalenceCounterexample)
    case inconclusive(LogicEquivalenceInconclusive)
}
