import LogicIR

internal enum LogicCellEventSemantics {
    static func edge(from old: LogicBit, to new: LogicBit, rising: Bool) -> Bool {
        if rising { return (old == .zero && new != .zero) || (!old.isKnown && new == .one) }
        return (old == .one && new != .one) || (!old.isKnown && new == .zero)
    }
    static func merge(_ a: LogicBit, _ b: LogicBit) -> LogicBit { a.isKnown && a == b ? a : .unknown }
    static func level(_ value: LogicBit, positive: Bool) -> LogicBit { positive ? (value == .highImpedance ? .unknown : value) : value.inverted }
    static func reset(_ reset: LogicBit, value: Bool, otherwise: LogicBit) -> LogicBit {
        let forced: LogicBit = value ? .one : .zero
        switch reset {
        case .zero: return otherwise
        case .one: return forced
        case .unknown, .highImpedance: return merge(forced, otherwise)
        }
    }
}
