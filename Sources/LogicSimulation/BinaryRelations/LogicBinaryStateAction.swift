public struct LogicBinaryStateAction: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case flipFlop(risingEdge: Bool), latch }
    public let kind: Kind
    public let control: Bool
    public let sampled: Bool
    public let asynchronous: Bool
    internal init(kind: Kind, control: Bool, sampled: Bool, asynchronous: Bool) {
        self.kind = kind; self.control = control; self.sampled = sampled; self.asynchronous = asynchronous
    }
}
