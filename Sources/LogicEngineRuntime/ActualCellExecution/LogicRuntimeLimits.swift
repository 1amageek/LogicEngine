import LogicKernelCore

public struct LogicRuntimeLimits: Sendable, Hashable, Codable {
    public let kernelMaximums: [UInt8: UInt64]
    public let maximumInputBytes: UInt64
    public let maximumOutputBytes: UInt64
    public let timeoutNanoseconds: UInt64
    public let maximumTokens: Int
    public let maximumTableEntries: Int
    public let maximumNesting: Int
    public let maximumCutInputs: Int
    public let maximumCellInputs: Int
    public let maximumCutsPerNode: Int
    public let firstLibraryEntityID: UInt64
    public let firstMappedEntityID: UInt64

    public init(kernelMaximums: [UInt8: UInt64], maximumInputBytes: UInt64, maximumOutputBytes: UInt64,
                timeoutNanoseconds: UInt64, maximumTokens: Int, maximumTableEntries: Int,
                maximumNesting: Int, maximumCutInputs: Int, maximumCellInputs: Int,
                maximumCutsPerNode: Int, firstLibraryEntityID: UInt64, firstMappedEntityID: UInt64) {
        self.kernelMaximums = kernelMaximums; self.maximumInputBytes = maximumInputBytes
        self.maximumOutputBytes = maximumOutputBytes; self.timeoutNanoseconds = timeoutNanoseconds
        self.maximumTokens = maximumTokens; self.maximumTableEntries = maximumTableEntries
        self.maximumNesting = maximumNesting; self.maximumCutInputs = maximumCutInputs
        self.maximumCellInputs = maximumCellInputs; self.maximumCutsPerNode = maximumCutsPerNode
        self.firstLibraryEntityID = firstLibraryEntityID; self.firstMappedEntityID = firstMappedEntityID
    }
    public func kernelLimits() throws(LogicKernelError) -> LogicKernelLimits {
        guard maximumInputBytes > 0, maximumOutputBytes > 0, timeoutNanoseconds > 0,
              maximumTokens > 0, maximumTableEntries > 0, maximumNesting > 0 else {
            throw .invalidInput("Host byte/time/syntax capacities must be positive")
        }
        var limits: [LogicResource: UInt64] = [:]
        for resource in LogicResource.allCases { limits[resource] = kernelMaximums[resource.rawValue] }
        guard kernelMaximums.count == limits.count else { throw .invalidInput("Unknown kernel resource limits") }
        return try .init(maximums: limits)
    }
}
