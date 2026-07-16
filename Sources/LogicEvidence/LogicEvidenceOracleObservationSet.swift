import Foundation

public struct LogicEvidenceOracleObservationSet: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var oracleImplementationID: String
    public var oracleImplementationVersion: String
    public var observations: [LogicEvidenceOracleObservation]

    public init(
        oracleImplementationID: String,
        oracleImplementationVersion: String,
        observations: [LogicEvidenceOracleObservation],
        schemaVersion: Int = LogicEvidenceOracleObservationSet.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.oracleImplementationID = oracleImplementationID
        self.oracleImplementationVersion = oracleImplementationVersion
        self.observations = observations.sorted { $0.caseID < $1.caseID }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicEvidenceError.invalidSuite("unsupported oracle observation schema version \(schemaVersion)")
        }
        guard !oracleImplementationID.isEmpty, !oracleImplementationVersion.isEmpty else {
            throw LogicEvidenceError.invalidSuite("oracle implementation identity is incomplete")
        }
        guard !observations.isEmpty else {
            throw LogicEvidenceError.invalidSuite("oracle observation set has no cases")
        }
        var caseIDs: Set<String> = []
        for observation in observations {
            guard !observation.caseID.isEmpty else {
                throw LogicEvidenceError.invalidSuite("oracle observation has an empty case ID")
            }
            guard caseIDs.insert(observation.caseID).inserted else {
                throw LogicEvidenceError.duplicateCase(observation.caseID)
            }
        }
    }
}
