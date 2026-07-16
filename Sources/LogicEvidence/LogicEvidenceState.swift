import Foundation

public enum LogicEvidenceState: String, Sendable, Hashable, Codable, CaseIterable {
    case unassessed
    case corpusChecked
    case oracleCorrelated
}
