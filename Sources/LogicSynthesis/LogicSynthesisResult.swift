import CircuiteFoundation
import Foundation
import LogicEngineCore

public struct LogicSynthesisResult: Sendable, Hashable, Codable {
    public let schemaVersion: Int
    public let runID: String
    public let status: LogicEngineCore.LogicExecutionStatus
    public let diagnostics: [DesignDiagnostic]
    public let artifacts: [ArtifactReference]
    public let metadata: LogicExecutionMetadata
    public let payload: LogicSynthesisPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: LogicEngineCore.LogicExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference],
        metadata: LogicExecutionMetadata,
        payload: LogicSynthesisPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.metadata = metadata
        self.payload = payload
    }
}
