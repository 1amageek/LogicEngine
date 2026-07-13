import Foundation
import XcircuitePackage

public struct LogicQualificationCaseEvaluation: Sendable, Hashable, Codable {
    public var caseID: String
    public var matched: Bool
    public var observedStatus: XcircuiteEngineExecutionStatus
    public var observedDiagnosticCodes: [String]
    public var observedArtifactIDs: [String]
    public var mismatches: [String]

    public init(
        caseID: String,
        matched: Bool,
        observedStatus: XcircuiteEngineExecutionStatus,
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
