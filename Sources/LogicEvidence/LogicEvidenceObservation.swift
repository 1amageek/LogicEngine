import Foundation
import LogicEngineCore
import LogicIR

public struct LogicEvidenceObservation: Sendable, Hashable, Codable {
    public var status: LogicExecutionStatus
    public var diagnosticCodes: [String]
    public var artifactIDs: [String]

    public init(
        status: LogicExecutionStatus,
        diagnosticCodes: [String] = [],
        artifactIDs: [String] = []
    ) {
        self.status = status
        self.diagnosticCodes = Array(Set(diagnosticCodes)).sorted()
        self.artifactIDs = Array(Set(artifactIDs)).sorted()
    }
}
