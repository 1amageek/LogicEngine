import LogicEngineCore

public protocol LogicSimulationArtifactLoading: Sendable {
    func load(_ acceptance: LogicArtifactBinding, expectedRequest: LogicSimulationRequest,
              limits: LogicRuntimeLimits) async throws -> LogicSimulationAcceptance
}
