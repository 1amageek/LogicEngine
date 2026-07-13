import Foundation
import LogicIR

public protocol LogicSimulationExecuting: Sendable {
    func execute(
        _ request: LogicSimulationRequest
    ) async throws -> LogicSimulationResult
}
