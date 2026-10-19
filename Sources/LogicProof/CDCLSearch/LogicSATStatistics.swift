public struct LogicSATStatistics: Sendable, Equatable {
    public internal(set) var decisions: UInt64 = 0
    public internal(set) var propagations: UInt64 = 0
    public internal(set) var conflicts: UInt64 = 0
    public internal(set) var learnedClauses: UInt64 = 0
    public internal(set) var backjumps: UInt64 = 0
    public internal(set) var nonChronologicalBackjumps: UInt64 = 0
    public internal(set) var watchRelocations: UInt64 = 0
    internal init() {}
}
