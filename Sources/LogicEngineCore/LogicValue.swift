import Foundation

public enum LogicValue: String, Sendable, Hashable, Codable, CaseIterable {
    case zero = "0"
    case one = "1"
    case unknown = "X"
    case highImpedance = "Z"

    public var isKnown: Bool {
        self == .zero || self == .one
    }

    public var inverted: LogicValue {
        switch self {
        case .zero:
            return .one
        case .one:
            return .zero
        case .unknown, .highImpedance:
            return .unknown
        }
    }

    public init(character: Character) throws {
        switch character.uppercased() {
        case "0": self = .zero
        case "1": self = .one
        case "X": self = .unknown
        case "Z": self = .highImpedance
        default: throw LogicExecutionError.invalidLogicValue(String(character))
        }
    }
}
