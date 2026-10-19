import LogicIR

public struct LogicMappingCandidate: Sendable {
    private final class Storage: Sendable {
        let source: BitLogicDesign
        let design: MappedGateDesign
        let statistics: LogicMappingStatistics
        let origins: [LogicMappingOrigin]
        init(source: BitLogicDesign, design: MappedGateDesign, statistics: LogicMappingStatistics,
             origins: consuming [LogicMappingOrigin]) {
            self.source = source; self.design = design; self.statistics = statistics; self.origins = origins
        }
    }
    private let storage: Storage
    public var source: BitLogicDesign { storage.source }
    public var design: MappedGateDesign { storage.design }
    public var statistics: LogicMappingStatistics { storage.statistics }
    internal init(source: BitLogicDesign, design: MappedGateDesign, statistics: LogicMappingStatistics,
                  origins: consuming [LogicMappingOrigin]) {
        storage = .init(source: source, design: design, statistics: statistics, origins: origins)
    }
    public borrowing func withOrigins<Result, Failure: Error>(
        _ body: (borrowing Span<LogicMappingOrigin>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let values = owner.origins
        defer { withExtendedLifetime(owner) {} }
        return try body(values.isEmpty ? Span() : values.span)
    }
}
