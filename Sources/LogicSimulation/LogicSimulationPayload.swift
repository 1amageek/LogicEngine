import Foundation
import XcircuitePackage
import LogicIR
import LogicEngineCore

public struct LogicSimulationPayload: Sendable, Hashable, Codable {
    public var traceCount: Int
    public var assertionFailureCount: Int
    public var eventCount: Int
    public var waveform: XcircuiteFileReference?
    public var assertionReport: XcircuiteFileReference?
    public var cancellationRecord: XcircuiteFileReference?
    public var finalValues: [String: LogicVector]

    public init(
        traceCount: Int,
        assertionFailureCount: Int,
        eventCount: Int = 0,
        waveform: XcircuiteFileReference? = nil,
        assertionReport: XcircuiteFileReference? = nil,
        cancellationRecord: XcircuiteFileReference? = nil,
        finalValues: [String: LogicVector] = [:]
    ) {
        self.traceCount = traceCount
        self.assertionFailureCount = assertionFailureCount
        self.eventCount = eventCount
        self.waveform = waveform
        self.assertionReport = assertionReport
        self.cancellationRecord = cancellationRecord
        self.finalValues = finalValues
    }

    private enum CodingKeys: String, CodingKey {
        case traceCount
        case assertionFailureCount
        case eventCount
        case waveform
        case assertionReport
        case cancellationRecord
        case finalValues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traceCount = try container.decode(Int.self, forKey: .traceCount)
        assertionFailureCount = try container.decode(Int.self, forKey: .assertionFailureCount)
        eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount) ?? traceCount
        waveform = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .waveform)
        assertionReport = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .assertionReport)
        cancellationRecord = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .cancellationRecord)
        finalValues = try container.decodeIfPresent([String: LogicVector].self, forKey: .finalValues) ?? [:]
    }
}
