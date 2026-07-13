import Foundation

public struct LogicCancellationRecord: Sendable, Hashable, Codable {
    public let runID: String
    public let engineID: String
    public let reason: String
    public let recordedAt: Date

    public init(
        runID: String,
        engineID: String,
        reason: String,
        recordedAt: Date = Date()
    ) {
        self.runID = runID
        self.engineID = engineID
        self.reason = reason
        self.recordedAt = recordedAt
    }
}
