import Foundation

public struct LogicConstraintDocument: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var maximumArea: Double?
    public var maximumPower: Double?
    public var maximumLogicDepth: Int?
    public var targetClockPeriod: Double?

    public init(
        schemaVersion: Int = LogicConstraintDocument.currentSchemaVersion,
        maximumArea: Double? = nil,
        maximumPower: Double? = nil,
        maximumLogicDepth: Int? = nil,
        targetClockPeriod: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.maximumArea = maximumArea
        self.maximumPower = maximumPower
        self.maximumLogicDepth = maximumLogicDepth
        self.targetClockPeriod = targetClockPeriod
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact("unsupported constraint schema version \(schemaVersion)")
        }
        if let maximumArea, maximumArea < 0 { throw LogicExecutionError.invalidArtifact("maximum area must be non-negative") }
        if let maximumPower, maximumPower < 0 { throw LogicExecutionError.invalidArtifact("maximum power must be non-negative") }
        if let maximumLogicDepth, maximumLogicDepth < 0 { throw LogicExecutionError.invalidArtifact("maximum logic depth must be non-negative") }
        if let targetClockPeriod, targetClockPeriod <= 0 { throw LogicExecutionError.invalidArtifact("target clock period must be positive") }
    }
}
