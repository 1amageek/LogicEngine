import Foundation

public enum LogicEvidenceError: Error, Sendable, Hashable, LocalizedError {
    case invalidSuite(String)
    case duplicateCase(String)
    case invalidReport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSuite(let message):
            "Invalid logic evidence suite: \(message)."
        case .duplicateCase(let caseID):
            "Logic evidence suite contains duplicate case \(caseID)."
        case .invalidReport(let message):
            "Invalid logic evidence report: \(message)."
        }
    }
}
