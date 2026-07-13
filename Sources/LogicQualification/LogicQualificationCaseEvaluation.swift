import Foundation
import LogicEngineCore

public struct LogicQualificationCaseEvaluation: Sendable, Hashable, Codable {
    public var caseID: String
    public var matched: Bool
    public var observedStatus: LogicExecutionStatus
    public var observedDiagnosticCodes: [String]
    public var observedArtifactIDs: [String]
    public var mismatches: [String]

    public init(
        caseID: String,
        matched: Bool,
        observedStatus: LogicExecutionStatus,
        observedDiagnosticCodes: [String],
        observedArtifactIDs: [String],
        mismatches: [String]
    ) {
        self.caseID = caseID
        self.matched = matched
        self.observedStatus = observedStatus
        self.observedDiagnosticCodes = observedDiagnosticCodes.sorted()
        self.observedArtifactIDs = observedArtifactIDs.sorted()
        self.mismatches = mismatches.sorted()
    }
}
