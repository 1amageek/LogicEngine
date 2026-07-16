import Foundation

public protocol LogicEvidenceExecuting: Sendable {
    func execute(
        _ request: LogicEvidenceRequest
    ) async throws -> LogicEvidenceObservation
}
