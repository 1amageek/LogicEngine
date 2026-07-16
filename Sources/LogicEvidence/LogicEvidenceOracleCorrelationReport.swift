import Foundation

public struct LogicEvidenceOracleCorrelationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var suiteID: String
    public var nativeImplementationID: String
    public var oracleImplementationID: String
    public var matchedCaseIDs: [String]
    public var mismatches: [String]

    public init(
        suiteID: String,
        nativeImplementationID: String,
        oracleImplementationID: String,
        matchedCaseIDs: [String] = [],
        mismatches: [String] = [],
        schemaVersion: Int = LogicEvidenceOracleCorrelationReport.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.nativeImplementationID = nativeImplementationID
        self.oracleImplementationID = oracleImplementationID
        self.matchedCaseIDs = matchedCaseIDs.sorted()
        self.mismatches = mismatches.sorted()
    }

    public var isUsableForPromotion: Bool {
        nativeImplementationID != oracleImplementationID && mismatches.isEmpty
    }


    public var matched: Bool { mismatches.isEmpty }

    public var independenceVerified: Bool {
        nativeImplementationID != oracleImplementationID
    }
}
