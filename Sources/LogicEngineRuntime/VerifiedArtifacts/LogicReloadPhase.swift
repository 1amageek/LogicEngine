import LogicKernelCore
import Synchronization

/// One exclusive source phase: real outer admission precedes every action.
internal final class LogicReloadPhase: Sendable {
    struct Usage: Sendable {
        var current: UInt64 = 0
        var peak: UInt64 = 0
        var allocations: UInt64 = 0
        var reservations: UInt64 = 0
        var work: UInt64 = 0
        var sealed = false
        var admitting = false
    }
    let resources: LogicReloadResources
    let originalControl: any LogicRunControlling
    private let state: Mutex<Usage>
    private let metadataLease: any LogicKernelStorageRetaining
    private let storageLimit: UInt64
    private let allocationLimit: UInt64
    private let reservationLimit: UInt64
    private let workLimit: UInt64

    static func make(context: inout LogicKernelContext, resources: LogicReloadResources) throws -> LogicReloadPhase {
        try context.requireAccounting(expected: resources)
        let originalControl = context.checkpointControl
        try originalControl.checkpoint(); try resources.checkCaller()
        let usage = context.usage
        let storage = context.limits[.managedStorageBytes] - usage[.managedStorageBytes]
        let allocation = context.limits[.allocationBytes] - usage[.allocationBytes]
        let reservations = context.limits[.storageReservations] - usage[.storageReservations]
        let work = context.limits[.workUnits] - usage[.workUnits]
        let bytes = UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<LogicReloadResources>.stride
            + MemoryLayout<any LogicRunControlling>.stride + MemoryLayout<Mutex<Usage>>.stride
            + MemoryLayout<any LogicKernelStorageRetaining>.stride + 4 * MemoryLayout<UInt64>.stride)
        _ = try add(0, bytes, resource: .managedStorageBytes, limit: storage)
        _ = try add(0, bytes, resource: .allocationBytes, limit: allocation)
        _ = try add(0, 1, resource: .storageReservations, limit: reservations)
        var committed = false
        let lease: any LogicKernelStorageRetaining
        do {
            lease = try resources.phaseReserve(byteCount: bytes) { committed = true }
            try originalControl.checkpoint(); try resources.checkCaller()
        } catch {
            if committed {
                do {
                    try context.importAccountedPhase(peakStorageBytes: bytes, allocationBytes: bytes,
                        storageReservations: 1, workUnits: 0, expectedAccounting: resources)
                } catch let secondary { throw LogicControlledReloadFailure(primary: resources.resolved(error), secondary: secondary) }
            }
            throw resources.resolved(error)
        }
        var initial = Usage()
        initial.current = bytes; initial.peak = bytes; initial.allocations = bytes; initial.reservations = 1
        return LogicReloadPhase(resources: resources, originalControl: originalControl, usage: initial,
            metadata: lease, storage: storage, allocation: allocation, reservations: reservations, work: work)
    }

    private init(resources: LogicReloadResources, originalControl: any LogicRunControlling,
        usage: Usage, metadata: any LogicKernelStorageRetaining,
        storage: UInt64, allocation: UInt64, reservations: UInt64, work: UInt64) {
        self.resources = resources; self.originalControl = originalControl
        self.state = Mutex(usage); self.metadataLease = metadata
        storageLimit = storage; allocationLimit = allocation
        reservationLimit = reservations; workLimit = work
    }

    func check() throws {
        do { try originalControl.checkpoint() }
        catch { resources.record(error); throw error }
        try resources.checkCaller()
    }

    func chargeWork(_ amount: UInt64) throws {
        try check()
        let next = try state.withLock { state throws(LogicKernelError) in
            guard !state.sealed, !state.admitting else { throw .invalidInput("Reload phase is sealed or reentrant") }
            let next = try Self.add(state.work, amount, resource: .workUnits, limit: workLimit)
            state.admitting = true
            return next
        }
        defer { state.withLock { $0.admitting = false } }
        try resources.phaseCharge(.workUnits, amount: amount) {
            state.withLock { $0.work = next }
        }
        try check()
    }

    func reserveStorage(_ bytes: UInt64) throws -> any LogicKernelStorageRetaining {
        try check()
        let metadata = UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<LogicReloadPhase>.stride
            + MemoryLayout<UInt64>.stride + MemoryLayout<any LogicKernelStorageRetaining>.stride)
        let total = bytes.addingReportingOverflow(metadata)
        guard !total.overflow else { throw LogicKernelError.invalidInput("Reload lease metadata overflows") }
        let offered = total.partialValue
        let next = try state.withLock { state throws(LogicKernelError) in
            guard !state.sealed, !state.admitting else { throw .invalidInput("Reload phase is sealed or reentrant") }
            let current = try Self.add(state.current, offered, resource: .managedStorageBytes, limit: storageLimit)
            let allocations = try Self.add(state.allocations, offered, resource: .allocationBytes, limit: allocationLimit)
            let reservations = try Self.add(state.reservations, 1, resource: .storageReservations, limit: reservationLimit)
            state.admitting = true
            return (current, allocations, reservations)
        }
        defer { state.withLock { $0.admitting = false } }
        var committed = false
        let lease: any LogicKernelStorageRetaining
        do {
            lease = try resources.phaseReserve(byteCount: offered) {
                state.withLock {
                    $0.current = next.0; $0.peak = max($0.peak, next.0)
                    $0.allocations = next.1; $0.reservations = next.2
                }
                committed = true
            }
            try check()
        } catch {
            if committed { state.withLock { $0.current -= offered } }
            throw error
        }
        // This owner also refunds phase live storage when the last lower lease releases.
        return Lease(phase: self, byteCount: offered, upstream: lease)
    }

    func importOnce(into context: inout LogicKernelContext) throws(LogicKernelError) {
        let usage = try state.withLock { state throws(LogicKernelError) in
            guard !state.sealed, !state.admitting else { throw .invalidInput("Reload phase already imported or active") }
            state.sealed = true
            return state
        }
        try context.importAccountedPhase(peakStorageBytes: usage.peak, allocationBytes: usage.allocations,
            storageReservations: usage.reservations, workUnits: usage.work, expectedAccounting: resources)
    }

    private static func add(_ lhs: UInt64, _ rhs: UInt64, resource: LogicResource,
                            limit: UInt64) throws(LogicKernelError) -> UInt64 {
        let sum = lhs.addingReportingOverflow(rhs)
        guard !sum.overflow, sum.partialValue <= limit else {
            throw .resourceLimit(resource: resource, limit: limit, requested: sum.overflow ? nil : sum.partialValue)
        }
        return sum.partialValue
    }

    private final class Lease: LogicKernelStorageRetaining {
        let phase: LogicReloadPhase
        let byteCount: UInt64
        let upstream: any LogicKernelStorageRetaining
        init(phase: LogicReloadPhase, byteCount: UInt64, upstream: any LogicKernelStorageRetaining) {
            self.phase = phase; self.byteCount = byteCount; self.upstream = upstream
        }
        deinit { phase.state.withLock { $0.current -= byteCount } }
    }
}
