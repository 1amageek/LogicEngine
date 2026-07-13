import Foundation

public struct LogicQualificationReleaseApproval: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var approvalID: String
    public var suiteID: String
    public var qualificationID: String
    public var approverIdentity: String
    public var rationale: String
    public var approved: Bool
    public var approvedAt: Date

    public init(
        approvalID: String,
        suiteID: String,
        qualificationID: String,
        approverIdentity: String,
        rationale: String,
        approved: Bool,
        approvedAt: Date = Date(),
        schemaVersion: Int = LogicQualificationReleaseApproval.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.approvalID = approvalID
        self.suiteID = suiteID
        self.qualificationID = qualificationID
        self.approverIdentity = approverIdentity
        self.rationale = rationale
        self.approved = approved
        self.approvedAt = approvedAt
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicQualificationError.invalidReleaseApproval(
                "unsupported release approval schema version \(schemaVersion)"
            )
        }
        let requiredValues = [approvalID, suiteID, qualificationID, approverIdentity]
        guard requiredValues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LogicQualificationError.invalidReleaseApproval(
                "release approval identity is incomplete"
            )
        }
        guard !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicQualificationError.invalidReleaseApproval(
                "release approval requires a rationale"
            )
        }
    }
}
