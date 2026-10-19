import LogicEngineCore

public protocol LogicSynthesisArtifactLoading: Sendable {
    func load(_ receipt: LogicArtifactBinding, limits: LogicRuntimeLimits) async throws -> LogicVerifiedSynthesis
}
