import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicSynthesisResult: Sendable, Hashable, Codable {
    public let schemaVersion: Int
    public let runID: String
    public let status: LogicIR.LogicExecutionStatus
    public let diagnostics: [DesignDiagnostic]
    public let artifacts: [ArtifactReference]
    public let provenance: ExecutionProvenance
    public let payload: LogicSynthesisPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: LogicIR.LogicExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference],
        provenance: ExecutionProvenance,
        payload: LogicSynthesisPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.provenance = provenance
        self.payload = payload
    }
}
