import Foundation
import XcircuitePackage

public struct LogicQualificationOracleObservation: Sendable, Hashable, Codable {
    public var caseID: String
    public var observation: LogicQualificationObservation

    public init(caseID: String, observation: LogicQualificationObservation) {
        self.caseID = caseID
        self.observation = observation
    }
}
