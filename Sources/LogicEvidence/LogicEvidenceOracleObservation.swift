import Foundation

public struct LogicEvidenceOracleObservation: Sendable, Hashable, Codable {
    public var caseID: String
    public var observation: LogicEvidenceObservation

    public init(caseID: String, observation: LogicEvidenceObservation) {
        self.caseID = caseID
        self.observation = observation
    }
}
