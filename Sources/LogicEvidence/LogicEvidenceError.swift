import Foundation

public enum LogicEvidenceError: Error, Sendable, Hashable, LocalizedError {
    case invalidSuite(String)
    case duplicateCase(String)
    case unsupportedRequest(String)
    case invalidReport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSuite(let message):
            "Invalid logic qualification suite: \(message)."
        case .duplicateCase(let caseID):
            "Logic qualification suite contains duplicate case \(caseID)."
        case .unsupportedRequest(let message):
            "Unsupported logic qualification request: \(message)."
        case .invalidReport(let message):
            "Invalid logic qualification report: \(message)."
        }
    }
}
