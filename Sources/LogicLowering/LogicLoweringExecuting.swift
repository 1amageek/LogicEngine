import Foundation

public protocol LogicLoweringExecuting: Sendable {
    func execute(
        _ request: LogicLoweringRequest
    ) async throws -> LogicLoweringResult
}
