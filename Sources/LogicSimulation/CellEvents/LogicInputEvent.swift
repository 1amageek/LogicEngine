import LogicIR

public struct LogicInputEvent: Sendable {
    public struct Update: Sendable {
        public let portIndex: Int
        public let value: LogicFourStateVector
        public init(portIndex: Int, value: LogicFourStateVector) { self.portIndex = portIndex; self.value = value }
    }
    public let time: UInt64
    internal let updates: [Update]
    public init(time: UInt64, updates: consuming [Update]) { self.time = time; self.updates = updates }
}
