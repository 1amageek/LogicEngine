import LogicEngineCore
import LogicKernelCore

public struct NativeLogicEquivalenceEngine: LogicEquivalenceExecuting {
    private let loader: any LogicSynthesisArtifactLoading
    public init(artifactStore: any LogicArtifactStoring) {
        loader = NativeLogicSynthesisEngine(artifactStore: artifactStore)
    }
    public func execute(_ request: LogicEquivalenceRequest) async throws -> LogicEquivalenceResult {
        guard request.schemaVersion == LogicEquivalenceRequest.currentSchemaVersion, !request.runID.isEmpty else {
            throw LogicKernelError.invalidInput("Unsupported actual-cell equivalence request")
        }
        let verified = try await loader.load(request.receipt, limits: request.limits)
        try verified.equivalence.requireBinding(to: verified.problem)
        return .init(runID: request.runID, receipt: request.receipt,
                     proof: verified.receipt.proof, proofKind: verified.receipt.proofKind)
    }
}
