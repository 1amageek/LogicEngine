import Foundation
import CircuiteFoundation
import LogicEngineCore

public struct LogicLoweringResult: Sendable, Hashable, Codable {
    public var status: LogicExecutionStatus
    public var document: LogicDesignDocument?
    public var payload: LogicLoweringPayload
    public var artifacts: [ArtifactReference]
    public var diagnostics: [DesignDiagnostic]

    public init(
        status: LogicExecutionStatus,
        document: LogicDesignDocument? = nil,
        payload: LogicLoweringPayload = LogicLoweringPayload(),
        artifacts: [ArtifactReference] = [],
        diagnostics: [DesignDiagnostic] = []
    ) {
        self.status = status
        self.document = document
        self.payload = payload
        self.artifacts = artifacts
        self.diagnostics = diagnostics
    }
}
