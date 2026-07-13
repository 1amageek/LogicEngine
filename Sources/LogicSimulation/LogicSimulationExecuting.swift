import Foundation
import XcircuitePackage
import LogicIR

public protocol LogicSimulationExecuting: Sendable {
    func execute(
        _ request: LogicSimulationRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicSimulationPayload>
}
