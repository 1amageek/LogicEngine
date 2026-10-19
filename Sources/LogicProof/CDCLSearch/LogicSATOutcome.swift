public enum LogicSATOutcome: Sendable {
    case satisfiable(LogicSATAssignment, LogicSATStatistics)
    case unsatisfiable(LogicRUPCertificate, LogicSATStatistics)
}
