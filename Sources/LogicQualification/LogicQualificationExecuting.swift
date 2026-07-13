import Foundation

public protocol LogicQualificationExecuting: Sendable {
    func execute(
        _ request: LogicQualificationRequest
    ) async throws -> LogicQualificationObservation
}
