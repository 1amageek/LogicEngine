import CircuiteFoundation

public struct LogicSimulationObservationRecord: Sendable, Hashable, Codable {
    public struct Output: Sendable, Hashable, Codable {
        public let portID: DesignEntityID
        public let portIndex: Int
        public let value: String
    }
    public let time: UInt64
    public let outputs: [Output]
}
