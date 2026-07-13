import Foundation
import XcircuitePackage

public protocol LogicBoundedTemporalEquivalenceExecuting: Sendable {
    func execute(
        _ request: LogicBoundedTemporalEquivalenceRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicBoundedTemporalEquivalencePayload>
}
