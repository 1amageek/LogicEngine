import Foundation

public struct LogicNodeKind: RawRepresentable, Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let and = LogicNodeKind(rawValue: "and")
    public static let or = LogicNodeKind(rawValue: "or")
    public static let logicalAnd = LogicNodeKind(rawValue: "logical_and")
    public static let logicalOr = LogicNodeKind(rawValue: "logical_or")
    public static let logicalNot = LogicNodeKind(rawValue: "logical_not")
    public static let xor = LogicNodeKind(rawValue: "xor")
    public static let nand = LogicNodeKind(rawValue: "nand")
    public static let nor = LogicNodeKind(rawValue: "nor")
    public static let xnor = LogicNodeKind(rawValue: "xnor")
    public static let not = LogicNodeKind(rawValue: "not")
    public static let buffer = LogicNodeKind(rawValue: "buffer")
    public static let constant = LogicNodeKind(rawValue: "constant")
    public static let concat = LogicNodeKind(rawValue: "concat")
    public static let slice = LogicNodeKind(rawValue: "slice")
    public static let caseEqual = LogicNodeKind(rawValue: "case_equal")
    public static let caseNotEqual = LogicNodeKind(rawValue: "case_not_equal")
    public static let equal = LogicNodeKind(rawValue: "equal")
    public static let notEqual = LogicNodeKind(rawValue: "not_equal")
    public static let lessThan = LogicNodeKind(rawValue: "less_than")
    public static let lessEqual = LogicNodeKind(rawValue: "less_equal")
    public static let greaterThan = LogicNodeKind(rawValue: "greater_than")
    public static let greaterEqual = LogicNodeKind(rawValue: "greater_equal")
    public static let add = LogicNodeKind(rawValue: "add")
    public static let subtract = LogicNodeKind(rawValue: "subtract")
    public static let multiply = LogicNodeKind(rawValue: "multiply")
    public static let divide = LogicNodeKind(rawValue: "divide")
    public static let modulo = LogicNodeKind(rawValue: "modulo")
    public static let shiftLeft = LogicNodeKind(rawValue: "shift_left")
    public static let shiftRight = LogicNodeKind(rawValue: "shift_right")
    public static let mux = LogicNodeKind(rawValue: "mux")
    public static let triState = LogicNodeKind(rawValue: "tri_state")
    public static let dff = LogicNodeKind(rawValue: "dff")
    public static let latch = LogicNodeKind(rawValue: "latch")

    public var isSequential: Bool {
        self == .dff || self == .latch
    }

    public var isSupported: Bool {
        switch self {
        case .and, .or, .logicalAnd, .logicalOr, .logicalNot, .xor, .nand, .nor, .xnor, .not, .buffer,
             .constant, .concat, .slice, .caseEqual, .caseNotEqual, .equal, .notEqual,
             .lessThan, .lessEqual, .greaterThan, .greaterEqual, .add, .subtract,
             .multiply, .divide, .modulo, .shiftLeft, .shiftRight, .mux, .triState,
             .dff, .latch:
            return true
        default:
            return false
        }
    }
}
