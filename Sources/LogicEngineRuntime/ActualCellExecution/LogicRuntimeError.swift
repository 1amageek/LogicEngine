import LogicProof

public enum LogicRuntimeError: Error, Sendable {
    case input(any Error)
    case codec(any Error)
    case library(any Error)
    case kernel(any Error)
    case proof(any Error)
    case timing(any Error)
    case persistence(any Error)
    case different(LogicEquivalenceCounterexample)
    case inconclusive(LogicEquivalenceInconclusive)
    case constraint(String)
    case unsupported(String)
}
