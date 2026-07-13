import Foundation

public struct LogicStimulusDocument: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var timeUnit: String
    public var events: [LogicStimulusEvent]
    public var assertions: [LogicAssertion]
    public var endTime: Int64?

    public init(
        schemaVersion: Int = LogicStimulusDocument.currentSchemaVersion,
        timeUnit: String = "ns",
        events: [LogicStimulusEvent],
        assertions: [LogicAssertion] = [],
        endTime: Int64? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.timeUnit = timeUnit
        self.events = events
        self.assertions = assertions
        self.endTime = endTime
    }

    public func validate(against design: LogicDesignDocument) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidStimulus("unsupported schema version \(schemaVersion)")
        }
        guard !timeUnit.isEmpty else {
            throw LogicExecutionError.invalidStimulus("time unit is empty")
        }
        let widths = Dictionary(uniqueKeysWithValues: design.signals.map { ($0.name, $0.width) })
        for event in events {
            guard event.time >= 0 else {
                throw LogicExecutionError.invalidStimulus("event time must be non-negative")
            }
            for (signal, value) in event.assignments {
                guard let width = widths[signal] else {
                    throw LogicExecutionError.unknownSignal(signal)
                }
                guard value.width == width else {
                    throw LogicExecutionError.vectorWidthMismatch(expected: width, actual: value.width)
                }
            }
        }
        for assertion in assertions {
            guard assertion.time >= 0 else {
                throw LogicExecutionError.invalidStimulus("assertion time must be non-negative")
            }
            guard let width = widths[assertion.signal] else {
                throw LogicExecutionError.unknownSignal(assertion.signal)
            }
            guard assertion.expected.width == width else {
                throw LogicExecutionError.vectorWidthMismatch(expected: width, actual: assertion.expected.width)
            }
        }
        if let endTime {
            guard endTime >= 0 else {
                throw LogicExecutionError.invalidStimulus("end time must be non-negative")
            }
        }
    }
}
