import Foundation

public enum LogicQualificationState: String, Sendable, Hashable, Codable, CaseIterable {
    case unassessed
    case corpusChecked
    case oracleCorrelated
    case processQualified
    case releaseEligible
}
