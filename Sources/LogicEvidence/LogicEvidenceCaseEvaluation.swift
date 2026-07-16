import Foundation
import LogicEngineCore

public struct LogicEvidenceCaseEvaluation: Sendable, Hashable, Codable {
    public var caseID: String
    public var observedStatus: LogicExecutionStatus
    public var observedDiagnosticCodes: [String]
    public var observedArtifactIDs: [String]
    public var mismatches: [String]

    public init(
        caseID: String,
        observedStatus: LogicExecutionStatus,
        observedDiagnosticCodes: [String],
        observedArtifactIDs: [String],
        mismatches: [String]
    ) {
        self.caseID = caseID
        self.observedStatus = observedStatus
        self.observedDiagnosticCodes = observedDiagnosticCodes.sorted()
        self.observedArtifactIDs = observedArtifactIDs.sorted()
        self.mismatches = mismatches.sorted()
    }

    public var matched: Bool { mismatches.isEmpty }
}
