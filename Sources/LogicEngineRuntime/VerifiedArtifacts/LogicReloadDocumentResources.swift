import LogicKernelCore
import PDKCore
import Synchronization

/// Maps actual bounded-decoder events to the same invocation phase, before action.
internal final class LogicReloadDocumentResources: PDKAdmissionResourceAccounting {
    let phase: LogicReloadPhase
    private let maximumNesting: UInt64
    private let nesting: Mutex<UInt64>
    private let metadata: any LogicKernelStorageRetaining

    static func make(phase: LogicReloadPhase, maximumNesting: Int) throws -> LogicReloadDocumentResources {
        guard maximumNesting > 0 else { throw LogicKernelError.invalidInput("Reload nesting ceiling must be positive") }
        let bytes = UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<LogicReloadPhase>.stride
            + MemoryLayout<UInt64>.stride + MemoryLayout<Mutex<UInt64>>.stride
            + MemoryLayout<any LogicKernelStorageRetaining>.stride)
        let metadata = try phase.reserveStorage(bytes)
        try phase.check()
        return .init(phase: phase, maximumNesting: UInt64(maximumNesting), metadata: metadata)
    }
    private init(phase: LogicReloadPhase, maximumNesting: UInt64, metadata: any LogicKernelStorageRetaining) {
        self.phase = phase; self.maximumNesting = maximumNesting
        self.nesting = Mutex(0); self.metadata = metadata
    }

    func check() throws(PDKAdmissionResourceError) {
        do { try phase.check() }
        catch { throw preserve(error) }
    }

    func charge(_ cost: PDKAdmissionCost) throws(PDKAdmissionResourceError) {
        guard !cost.dimension.isLiveCapacity else { throw .invalidCost }
        do {
            // Each scalar/element/validation event is scheduled decoder work, not storage.
            try phase.chargeWork(cost.amount)
        } catch { throw preserve(error) }
    }

    func reserve(_ cost: PDKAdmissionCost) throws(PDKAdmissionResourceError) -> PDKAdmissionReservation {
        guard cost.accountingVersion == PDKAdmissionCost.currentAccountingVersion else {
            throw .unsupportedAccountingVersion(cost.accountingVersion)
        }
        do {
            try phase.check()
            switch cost.dimension {
            case .liveOwnedBytes, .temporaryBytes:
                let reservation = try phase.reserveStorage(cost.amount)
                return .init(cost: cost) { withExtendedLifetime(reservation) {} }
            case .decodeNesting, .includeDepth:
                try nesting.withLock { depth throws(PDKAdmissionResourceError) in
                    let next = depth.addingReportingOverflow(cost.amount)
                    guard !next.overflow, next.partialValue <= maximumNesting else {
                        throw .exhausted(dimension: cost.dimension, limit: maximumNesting,
                                         attempted: next.overflow ? .max : next.partialValue)
                    }
                    depth = next.partialValue
                }
                do { try phase.check() }
                catch {
                    nesting.withLock { $0 -= cost.amount }
                    throw error
                }
                return .init(cost: cost) { [self] in nesting.withLock { $0 -= cost.amount } }
            default:
                guard !cost.dimension.isLiveCapacity else {
                    throw PDKAdmissionResourceError.unsupportedBudgetCapability("Unsupported reload document extent")
                }
                try phase.chargeWork(cost.amount)
                return .init(cost: cost, onRelease: {})
            }
        } catch { throw preserve(error) }
    }

    private func preserve(_ error: any Error) -> PDKAdmissionResourceError {
        phase.resources.record(error)
        return .unsupportedBudgetCapability("Caller accounting failed; original cause retained by invocation.")
    }
}
