import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicSimulationResult: Sendable, Hashable, Codable {
    public let status: LogicExecutionStatus
    public let payload: LogicSimulationPayload
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]

    public init(
        status: LogicExecutionStatus,
        payload: LogicSimulationPayload,
        artifacts: [ArtifactReference] = [],
        diagnostics: [DesignDiagnostic] = []
    ) {
        self.status = status
        self.payload = payload
        self.artifacts = artifacts
        self.diagnostics = diagnostics
    }
}
