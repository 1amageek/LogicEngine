import LogicIR

public struct LogicOptimizationCandidate: Sendable {
    private final class Storage: Sendable {
        let source: BitLogicDesign
        let design: BitLogicDesign
        let origins: [LogicOptimizationOrigin]
        let statistics: LogicOptimizationStatistics
        init(source: BitLogicDesign, design: BitLogicDesign, origins: consuming [LogicOptimizationOrigin], statistics: LogicOptimizationStatistics) {
            self.source = source; self.design = design; self.origins = origins; self.statistics = statistics
        }
    }
    private let storage: Storage
    public var source: BitLogicDesign { storage.source }
    public var design: BitLogicDesign { storage.design }
    public var statistics: LogicOptimizationStatistics { storage.statistics }
    internal init(source: BitLogicDesign, design: BitLogicDesign, origins: consuming [LogicOptimizationOrigin], statistics: LogicOptimizationStatistics) {
        storage = Storage(source: source, design: design, origins: origins, statistics: statistics)
    }
    internal static var storageByteCount: Int {
        MemoryLayout<(BitLogicDesign, BitLogicDesign, [LogicOptimizationOrigin], LogicOptimizationStatistics)>.stride
    }
    public borrowing func withOrigins<Result, Failure: Error>(_ body: (borrowing Span<LogicOptimizationOrigin>) throws(Failure) -> Result) throws(Failure) -> Result {
        let owner = storage; let origins = owner.origins
        defer { withExtendedLifetime(owner) {} }
        return try body(origins.isEmpty ? Span() : origins.span)
    }
}
