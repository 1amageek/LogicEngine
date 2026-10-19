public struct LogicBinaryEventObservation: Sendable {
    public let observation: LogicBinaryObservation
    private final class Storage: Sendable {
        let states: [Bool]
        init(states: consuming [Bool]) { self.states = states }
    }
    private let storage: Storage
    internal static var storageByteCount: UInt64 { UInt64(MemoryLayout<[Bool]>.stride + MemoryLayout<Self>.stride) }
    internal init(observation: LogicBinaryObservation, states: consuming [Bool]) { self.observation = observation; storage = .init(states: states) }
    public borrowing func withStates<Result, Failure: Error>(_ body: (borrowing Span<Bool>) throws(Failure) -> Result) throws(Failure) -> Result {
        let owner = storage; let states = owner.states
        defer { withExtendedLifetime(owner) {} }
        return try body(states.span)
    }
}
