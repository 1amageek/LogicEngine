import Foundation
import LogicEngineCore

public enum LogicUnboundedTemporalEquivalenceDomain: String, Sendable, Hashable, Codable {
    case twoState
    case fourState

    public var values: [LogicValue] {
        switch self {
        case .twoState:
            return [.zero, .one]
        case .fourState:
            return [.zero, .one, .unknown, .highImpedance]
        }
    }
}
