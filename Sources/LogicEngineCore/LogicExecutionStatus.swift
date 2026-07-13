import Foundation

/// Execution state exposed by the Foundation-native LogicEngine boundary.
public enum LogicExecutionStatus: String, Sendable, Hashable, Codable {
    case completed
    case failed
    case blocked
    case cancelled
}
