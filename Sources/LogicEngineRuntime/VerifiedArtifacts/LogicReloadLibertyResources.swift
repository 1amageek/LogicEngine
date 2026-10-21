import LogicKernelCore
import Synchronization
import TimingCore

/// Parse forwarding ends only when the original validator's inout-context hooks take over.
internal final class LogicReloadLibertyResources: LibertySourceResourceAccounting {
    private let phase: LogicReloadPhase
    private let contextMediated: Mutex<Bool>
    private let metadata: any LogicKernelStorageRetaining
    static func make(phase: LogicReloadPhase) throws -> LogicReloadLibertyResources {
        let bytes = UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<LogicReloadPhase>.stride
            + MemoryLayout<Mutex<Bool>>.stride + MemoryLayout<any LogicKernelStorageRetaining>.stride)
        let metadata = try phase.reserveStorage(bytes)
        try phase.check()
        return .init(phase: phase, metadata: metadata)
    }
    private init(phase: LogicReloadPhase, metadata: any LogicKernelStorageRetaining) {
        self.phase = phase; self.contextMediated = Mutex(false); self.metadata = metadata
    }

    func check() throws {
        do { try phase.check() }
        catch { phase.resources.record(error); throw error }
    }

    func chargeWork(_ amount: UInt64) throws {
        try check()
        do {
            if !contextMediated.withLock({ $0 }) { try phase.chargeWork(amount) }
            try check()
        } catch { phase.resources.record(error); throw error }
    }

    func reserveStorage(kind: LibertySourceStorageKind, byteCount: UInt64)
        throws -> LibertySourceStorageReservation {
        try check()
        if contextMediated.withLock({ $0 }) {
            // LibertyNormalPowerValidator.reserve invoked its exact context hook first.
            return .init(kind: kind, byteCount: byteCount, release: {})
        }
        do {
            let reservation = try phase.reserveStorage(byteCount)
            try check()
            return .init(kind: kind, byteCount: byteCount) { withExtendedLifetime(reservation) {} }
        } catch { phase.resources.record(error); throw error }
    }

    func finishParse(into context: inout LogicKernelContext) throws(LogicKernelError) {
        try phase.importOnce(into: &context)
        contextMediated.withLock { $0 = true }
    }
}
