import Foundation
import LogicEngineCore
import LogicSimulation
import LogicSynthesis
import XcircuitePackage

public struct NativeLogicQualificationExecutor: LogicQualificationExecuting {
    public let simulation: any LogicSimulationExecuting
    public let synthesis: any LogicSynthesisExecuting
    public let unbounded: (any LogicUnboundedTemporalEquivalenceFoundationEngine)?

    public init(
        simulation: any LogicSimulationExecuting,
        synthesis: any LogicSynthesisExecuting,
        unbounded: (any LogicUnboundedTemporalEquivalenceFoundationEngine)? = nil
    ) {
        self.simulation = simulation
        self.synthesis = synthesis
        self.unbounded = unbounded
    }

    public func execute(
        _ request: LogicQualificationRequest
    ) async throws -> LogicQualificationObservation {
        try request.validate()
        switch request {
        case .simulation(let simulationRequest):
            let envelope = try await simulation.execute(simulationRequest)
            return LogicQualificationObservation(
                status: envelope.status,
                diagnosticCodes: envelope.diagnostics.map(\.code),
                artifactIDs: envelope.artifacts.compactMap(\.artifactID)
            )
        case .synthesis(let synthesisRequest):
            let envelope = try await synthesis.execute(synthesisRequest)
            return LogicQualificationObservation(
                status: envelope.status,
                diagnosticCodes: envelope.diagnostics.map(\.code),
                artifactIDs: envelope.artifacts.compactMap(\.artifactID)
            )
        case .unbounded(let unboundedRequest):
            guard let unbounded else {
                throw LogicQualificationError.unsupportedRequest("unbounded equivalence executor is not configured")
            }
            let result = try await unbounded.execute(unboundedRequest)
            return LogicQualificationObservation(
                status: legacyStatus(for: result.status),
                diagnosticCodes: result.diagnostics.map { $0.code.rawValue },
                artifactIDs: result.artifacts.map { $0.id.rawValue }
            )
        }
    }

    private func legacyStatus(for status: LogicExecutionStatus) -> XcircuiteEngineExecutionStatus {
        switch status {
        case .completed: return .completed
        case .failed: return .failed
        case .blocked: return .blocked
        case .cancelled: return .cancelled
        }
    }
}
