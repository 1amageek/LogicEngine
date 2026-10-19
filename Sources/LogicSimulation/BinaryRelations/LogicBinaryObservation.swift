public struct LogicBinaryObservation: Sendable {
    private final class Storage: Sendable {
        let outputs: [Bool]
        let actions: [LogicBinaryStateAction]
        init(outputs: consuming [Bool], actions: consuming [LogicBinaryStateAction]) { self.outputs = outputs; self.actions = actions }
    }
    private let storage: Storage
    internal static var storageByteCount: UInt64 { UInt64(MemoryLayout<([Bool], [LogicBinaryStateAction])>.stride + MemoryLayout<Self>.stride) }
    internal init(outputs: consuming [Bool], actions: consuming [LogicBinaryStateAction]) { storage = .init(outputs: outputs, actions: actions) }
    public var outputCount: Int { storage.outputs.count }
    public var stateCount: Int { storage.actions.count }
    public borrowing func withTables<Result, Failure: Error>(
        _ body: (borrowing Span<Bool>, borrowing Span<LogicBinaryStateAction>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let outputs = owner.outputs; let actions = owner.actions
        defer { withExtendedLifetime(owner) {} }
        return try body(outputs.span, actions.span)
    }
}
