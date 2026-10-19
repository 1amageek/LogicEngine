import LogicIR

public struct LogicOptimizationOrigin: Sendable, Equatable {
    public let source: BitNodeIndex
    public let destination: BitNodeIndex?
    internal init(source: BitNodeIndex, destination: BitNodeIndex?) {
        self.source = source; self.destination = destination
    }
}
