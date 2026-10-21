import LogicKernelCore
import Synchronization
import TimingCore

internal final class LogicLibertyRuntimeResources: LibertySourceResourceAccounting {
    struct State { var current: UInt64 = 0; var peak: UInt64 = 0; var work: UInt64 = 0; var allocations: UInt64 = 0 }
    private let state = Mutex(State())
    let maximumStorage: UInt64
    let maximumWork: UInt64
    let maximumAllocations: UInt64
    let control: any LogicRunControlling
    init(maximumStorage: UInt64, maximumWork: UInt64, maximumAllocations: UInt64, control: any LogicRunControlling) {
        self.maximumStorage = maximumStorage; self.maximumWork = maximumWork
        self.maximumAllocations = maximumAllocations; self.control = control
    }
    var usage: State { state.withLock { $0 } }
    func check() throws { try control.checkpoint() }
    func chargeWork(_ amount: UInt64) throws {
        try check()
        try state.withLock {
            let next = $0.work.addingReportingOverflow(amount)
            guard !next.overflow, next.partialValue <= maximumWork else {
                throw LogicKernelError.resourceLimit(resource: .workUnits, limit: maximumWork, requested: next.overflow ? nil : next.partialValue)
            }
            $0.work = next.partialValue
        }
    }
    func reserveStorage(kind: LibertySourceStorageKind, byteCount: UInt64) throws -> LibertySourceStorageReservation {
        try check()
        try state.withLock {
            let next = $0.current.addingReportingOverflow(byteCount)
            let total = $0.allocations.addingReportingOverflow(byteCount)
            guard !next.overflow, next.partialValue <= maximumStorage,
                  !total.overflow, total.partialValue <= maximumAllocations else {
                throw LogicKernelError.resourceLimit(resource: .managedStorageBytes, limit: maximumStorage, requested: nil)
            }
            $0.current = next.partialValue; $0.peak = max($0.peak, $0.current); $0.allocations = total.partialValue
        }
        return .init(kind: kind, byteCount: byteCount) { [self] in state.withLock { $0.current -= byteCount } }
    }
}
