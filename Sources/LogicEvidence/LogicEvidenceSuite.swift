import Foundation

public struct LogicEvidenceSuite: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var suiteID: String
    public var implementationID: String
    public var implementationVersion: String
    public var cases: [LogicEvidenceCase]

    public init(
        suiteID: String,
        implementationID: String,
        implementationVersion: String,
        cases: [LogicEvidenceCase],
        schemaVersion: Int = LogicEvidenceSuite.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.cases = cases
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicEvidenceError.invalidSuite("unsupported schema version \(schemaVersion)")
        }
        guard !suiteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !implementationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !implementationVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicEvidenceError.invalidSuite("suite identity is incomplete")
        }
        guard !cases.isEmpty else {
            throw LogicEvidenceError.invalidSuite("suite has no cases")
        }
        var caseIDs: Set<String> = []
        for evidenceCase in cases {
            try evidenceCase.validate()
            guard caseIDs.insert(evidenceCase.caseID).inserted else {
                throw LogicEvidenceError.duplicateCase(evidenceCase.caseID)
            }
        }
    }
}
