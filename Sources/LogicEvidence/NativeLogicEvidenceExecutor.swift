import Foundation
import LogicEngineCore
import LogicSimulation
import LogicSynthesis

public struct NativeLogicEvidenceExecutor: LogicEvidenceExecuting {
    public let simulation: any LogicSimulationExecuting
    public let synthesis: any LogicSynthesisExecuting
    public let unbounded: (any LogicUnboundedTemporalEquivalenceExecuting)?

    public init(
        simulation: any LogicSimulationExecuting,
        synthesis: any LogicSynthesisExecuting,
        unbounded: (any LogicUnboundedTemporalEquivalenceExecuting)? = nil
    ) {
        self.simulation = simulation
        self.synthesis = synthesis
        self.unbounded = unbounded
    }

    public func execute(
        _ request: LogicEvidenceRequest
    ) async throws -> LogicEvidenceObservation {
        try request.validate()
        switch request {
        case .simulation(let simulationRequest):
            let result = try await simulation.execute(simulationRequest)
            return LogicEvidenceObservation(
                status: result.status,
                diagnosticCodes: result.diagnostics.map { $0.code.rawValue },
                artifactIDs: result.artifacts.compactMap(\.artifactID)
            )
        case .synthesis(let synthesisRequest):
            let result = try await synthesis.execute(synthesisRequest)
            return LogicEvidenceObservation(
                status: result.status,
                diagnosticCodes: result.diagnostics.map { $0.code.rawValue },
                artifactIDs: result.artifacts.compactMap(\.artifactID)
            )
        case .unbounded(let unboundedRequest):
            guard let unbounded else {
                throw LogicEvidenceError.unsupportedRequest("unbounded equivalence executor is not configured")
            }
            let result = try await unbounded.execute(unboundedRequest)
            return LogicEvidenceObservation(
                status: result.status,
                diagnosticCodes: result.diagnostics.map { $0.code.rawValue },
                artifactIDs: result.artifacts.map { $0.id.description }
            )
        }
    }

}
