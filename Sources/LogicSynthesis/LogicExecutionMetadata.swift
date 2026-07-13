import Foundation

/// Internal execution timing captured by a synthesis domain result.
public struct LogicExecutionMetadata: Sendable, Hashable, Codable {
    public let engineID: String
    public let implementationID: String
    public let implementationVersion: String
    public let startedAt: Date
    public let completedAt: Date
    public let seed: UInt64?

    public init(
        engineID: String,
        implementationID: String,
        implementationVersion: String,
        startedAt: Date,
        completedAt: Date,
        seed: UInt64? = nil
    ) {
        self.engineID = engineID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.seed = seed
    }
}
