import Foundation
import XcircuitePackage

public protocol LogicLoweringExecuting: Sendable {
    func execute(
        _ request: LogicLoweringRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicLoweringPayload>
}
