import Foundation

public struct LogicQualificationOracleCorrelationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var suiteID: String
    public var nativeImplementationID: String
    public var oracleImplementationID: String
    public var matched: Bool
    public var independenceVerified: Bool
    public var matchedCaseIDs: [String]
    public var mismatches: [String]

    public init(
        suiteID: String,
        nativeImplementationID: String,
        oracleImplementationID: String,
        matched: Bool,
        independenceVerified: Bool,
        matchedCaseIDs: [String] = [],
        mismatches: [String] = [],
        schemaVersion: Int = LogicQualificationOracleCorrelationReport.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.nativeImplementationID = nativeImplementationID
        self.oracleImplementationID = oracleImplementationID
        self.matched = matched
        self.independenceVerified = independenceVerified
        self.matchedCaseIDs = matchedCaseIDs.sorted()
        self.mismatches = mismatches.sorted()
    }

    public var isUsableForPromotion: Bool {
        matched && independenceVerified && mismatches.isEmpty
    }
}
