import Foundation

/// Errors raised when a logic execution request violates its contract.
public enum LogicExecutionContractError: Error, Sendable, Equatable, Hashable, LocalizedError {
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            "Logic execution request is invalid: \(message)"
        }
    }
}
