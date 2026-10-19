import LogicKernelCore

public struct LogicSATVariable: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) throws(LogicKernelError) {
        guard rawValue > 0 else { throw .invalidInput("SAT variable must be a positive one-based index") }
        self.rawValue = rawValue
    }
    internal init(validated rawValue: Int) { self.rawValue = rawValue }
}
