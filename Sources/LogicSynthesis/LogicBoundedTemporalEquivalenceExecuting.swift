import Foundation

public protocol LogicBoundedTemporalEquivalenceExecuting: Sendable {
    func execute(
        _ request: LogicBoundedTemporalEquivalenceRequest
    ) async throws -> LogicBoundedTemporalEquivalenceResult
}
