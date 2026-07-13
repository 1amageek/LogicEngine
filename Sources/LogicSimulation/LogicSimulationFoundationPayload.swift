import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Foundation-native simulation metrics and artifact projections.
public struct LogicSimulationFoundationPayload: Sendable, Hashable, Codable {
    public let traceCount: Int
    public let assertionFailureCount: Int
    public let eventCount: Int
    public let waveform: ArtifactReference?
    public let assertionReport: ArtifactReference?
    public let cancellationRecord: ArtifactReference?
    public let finalValues: [String: LogicVector]

    public init(
        traceCount: Int,
        assertionFailureCount: Int,
        eventCount: Int = 0,
        waveform: ArtifactReference? = nil,
        assertionReport: ArtifactReference? = nil,
        cancellationRecord: ArtifactReference? = nil,
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
}
