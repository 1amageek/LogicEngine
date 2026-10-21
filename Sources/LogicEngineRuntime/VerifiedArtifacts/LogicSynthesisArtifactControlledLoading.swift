import LogicEngineCore
import LogicKernelCore

public protocol LogicSynthesisArtifactControlledLoading: Sendable {
    nonisolated(nonsending) func load(_ receipt: LogicArtifactBinding, limits: LogicRuntimeLimits,
        context: inout LogicKernelContext, resources: LogicReloadResources) async throws
        -> (value: LogicVerifiedSynthesis, retention: LogicReloadRetention)
}
