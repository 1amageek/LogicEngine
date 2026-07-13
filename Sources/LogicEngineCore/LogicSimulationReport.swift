import Foundation

public struct LogicSimulationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var eventCount: Int
    public var samples: [LogicWaveformSample]
    public var assertions: [LogicAssertionResult]

    public init(
        schemaVersion: Int = LogicSimulationReport.currentSchemaVersion,
        runID: String,
        eventCount: Int,
        samples: [LogicWaveformSample],
        assertions: [LogicAssertionResult]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.eventCount = eventCount
        self.samples = samples
        self.assertions = assertions
    }
}
