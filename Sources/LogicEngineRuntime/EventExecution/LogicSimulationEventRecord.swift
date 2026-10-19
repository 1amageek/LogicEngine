public struct LogicSimulationEventRecord: Sendable, Hashable, Codable {
    public struct Update: Sendable, Hashable, Codable {
        public let portIndex: Int
        public let value: String
        public init(portIndex: Int, value: String) { self.portIndex = portIndex; self.value = value }
    }
    public let time: UInt64
    public let updates: [Update]
    public init(time: UInt64, updates: [Update]) { self.time = time; self.updates = updates }
}
