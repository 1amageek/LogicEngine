import Foundation

public struct LogicQualificationSuite: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var suiteID: String
    public var implementationID: String
    public var implementationVersion: String
    public var cases: [LogicQualificationCase]

    public init(
        suiteID: String,
        implementationID: String,
        implementationVersion: String,
        cases: [LogicQualificationCase],
        schemaVersion: Int = LogicQualificationSuite.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.cases = cases
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicQualificationError.invalidSuite("unsupported schema version \(schemaVersion)")
        }
        guard !suiteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !implementationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !implementationVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicQualificationError.invalidSuite("suite identity is incomplete")
        }
        guard !cases.isEmpty else {
            throw LogicQualificationError.invalidSuite("suite has no cases")
        }
        var caseIDs: Set<String> = []
        for qualificationCase in cases {
            try qualificationCase.validate()
            guard caseIDs.insert(qualificationCase.caseID).inserted else {
                throw LogicQualificationError.duplicateCase(qualificationCase.caseID)
            }
        }
    }
}
