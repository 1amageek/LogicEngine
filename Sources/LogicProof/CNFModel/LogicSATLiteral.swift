import LogicKernelCore

public struct LogicSATLiteral: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) throws(LogicKernelError) {
        guard rawValue != 0, rawValue != Int.min else { throw .invalidInput("SAT literal must be nonzero and have a representable magnitude") }
        self.rawValue = rawValue
    }
    public init(variable: LogicSATVariable, positive: Bool = true) {
        rawValue = positive ? variable.rawValue : -variable.rawValue
    }
    private init(validated rawValue: Int) { self.rawValue = rawValue }
    public var variable: LogicSATVariable { .init(validated: rawValue > 0 ? rawValue : -rawValue) }
    public var isPositive: Bool { rawValue > 0 }
    public var negated: Self { .init(validated: -rawValue) }
}
