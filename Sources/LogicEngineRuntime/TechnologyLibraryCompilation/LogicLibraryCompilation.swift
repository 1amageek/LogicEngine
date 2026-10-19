import CircuiteFoundation
import LogicIR

public struct LogicLibraryCompilation: Sendable {
    internal final class Storage: Sendable {
        let source: ArtifactID
        let library: LogicTechnologyLibrary?
        let cells: [LogicLibraryCellEligibility]
        let normalPower: LogicLibraryNormalPower
        let policies: [LogicOperatingConditionPolicy]
        init(source: ArtifactID, library: LogicTechnologyLibrary?, cells: consuming [LogicLibraryCellEligibility],
             normalPower: LogicLibraryNormalPower, policies: [LogicOperatingConditionPolicy]) {
            self.source = source; self.library = library; self.cells = cells
            self.normalPower = normalPower; self.policies = policies
        }
    }
    private let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var source: ArtifactID { storage.source }
    public var library: LogicTechnologyLibrary? { storage.library }
    public var cellCount: Int { storage.cells.count }
    internal var normalPower: LogicLibraryNormalPower { storage.normalPower }
    internal var operatingConditionPolicies: [LogicOperatingConditionPolicy] { storage.policies }
    public borrowing func withCells<Result, Failure: Error>(
        _ body: (borrowing Span<LogicLibraryCellEligibility>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let cells = owner.cells
        defer { withExtendedLifetime(owner) {} }
        return try body(cells.isEmpty ? Span() : cells.span)
    }
}
