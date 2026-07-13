import Foundation

public struct LogicQualificationOracleObservationSet: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var oracleImplementationID: String
    public var oracleImplementationVersion: String
    public var observations: [LogicQualificationOracleObservation]

    public init(
        oracleImplementationID: String,
        oracleImplementationVersion: String,
        observations: [LogicQualificationOracleObservation],
        schemaVersion: Int = LogicQualificationOracleObservationSet.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.oracleImplementationID = oracleImplementationID
        self.oracleImplementationVersion = oracleImplementationVersion
        self.observations = observations.sorted { $0.caseID < $1.caseID }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicQualificationError.invalidSuite("unsupported oracle observation schema version \(schemaVersion)")
        }
        guard !oracleImplementationID.isEmpty, !oracleImplementationVersion.isEmpty else {
            throw LogicQualificationError.invalidSuite("oracle implementation identity is incomplete")
        }
        guard !observations.isEmpty else {
            throw LogicQualificationError.invalidSuite("oracle observation set has no cases")
        }
        var caseIDs: Set<String> = []
        for observation in observations {
            guard !observation.caseID.isEmpty else {
                throw LogicQualificationError.invalidSuite("oracle observation has an empty case ID")
            }
            guard caseIDs.insert(observation.caseID).inserted else {
                throw LogicQualificationError.duplicateCase(observation.caseID)
            }
        }
    }
}
