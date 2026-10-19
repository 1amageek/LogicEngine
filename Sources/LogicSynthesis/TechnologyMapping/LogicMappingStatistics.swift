public struct LogicMappingStatistics: Sendable, Equatable {
    public let instanceCount: Int
    public let area: Double
    public let combinationalDepth: Int
    internal init(instanceCount: Int, area: Double, combinationalDepth: Int) {
        self.instanceCount = instanceCount; self.area = area; self.combinationalDepth = combinationalDepth
    }
}
