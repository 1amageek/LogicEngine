import CircuiteFoundation
import LogicIR
import LogicKernelCore

public struct LogicObservation: Sendable {
    public struct Output: Sendable {
        public let portID: DesignEntityID
        public let portIndex: Int
        public let value: LogicFourStateVector
    }
    private final class Storage: Sendable {
        let outputs: [Output]
        init(outputs: consuming [Output]) { self.outputs = outputs }
    }
    public let time: UInt64
    private let storage: Storage
    internal init(time: UInt64, outputs: consuming [Output]) { self.time = time; storage = Storage(outputs: outputs) }
    public var outputCount: Int { storage.outputs.count }
    public func output(at index: Int) throws(LogicKernelError) -> Output {
        guard storage.outputs.indices.contains(index) else { throw .invalidInput("Observation output index is outside the model") }
        return storage.outputs[index]
    }
    public borrowing func withOutputs<Result, Failure: Error>(
        _ body: (borrowing Span<Output>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let outputs = owner.outputs
        defer { withExtendedLifetime(owner) {} }
        return try body(outputs.isEmpty ? Span() : outputs.span)
    }
}
