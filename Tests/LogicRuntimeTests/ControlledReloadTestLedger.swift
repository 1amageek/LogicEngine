import CircuiteFoundationFileSystem
import LogicEngineRuntime
import LogicKernelCore
import Synchronization

final class ControlledReloadTestLedger: LogicReloadResourceControlling {
    enum Failure: Error, Equatable { case cancelled, quota }
    struct State: Sendable {
        var live: UInt64 = 0
        var peak: UInt64 = 0
        var allocations: UInt64 = 0
        var reservations: UInt64 = 0
        var work: UInt64 = 0
        var read: UInt64 = 0
        var hashed: UInt64 = 0
        var open: UInt64 = 0
        var cancelled = false
        var callbacksAfterCancellation = 0
        var callbacksAfterOriginalCancellation = 0
    }
    private let state = Mutex(State())
    private let maximumLive: UInt64
    private let maximumWork: UInt64
    private let cancelAtReservation: UInt64?
    private let cancelAtWork: UInt64?
    private let original: ControlledReloadTestControl?
    private let cancelOriginalAtReservation: UInt64?
    init(maximumLive: UInt64 = 1_000_000_000, maximumWork: UInt64 = 10_000_000_000,
         cancelAtReservation: UInt64? = nil, cancelAtWork: UInt64? = nil,
         original: ControlledReloadTestControl? = nil, cancelOriginalAtReservation: UInt64? = nil) {
        self.maximumLive = maximumLive; self.maximumWork = maximumWork
        self.cancelAtReservation = cancelAtReservation; self.cancelAtWork = cancelAtWork
        self.original = original; self.cancelOriginalAtReservation = cancelOriginalAtReservation
    }
    var snapshot: State { state.withLock { $0 } }
    func cancel() { state.withLock { $0.cancelled = true } }
    func check() throws {
        if state.withLock({ $0.cancelled }) { throw Failure.cancelled }
    }
    func observeBitWidth(_ width: UInt64) throws { try check() }
    func charge(_ resource: LogicResource, amount: UInt64) throws {
        let originalCancelled = original?.isCancelled ?? false
        try state.withLock {
            if originalCancelled { $0.callbacksAfterOriginalCancellation += 1 }
            if $0.cancelled { $0.callbacksAfterCancellation += 1; throw Failure.cancelled }
            if resource == .workUnits {
                let total = $0.work.addingReportingOverflow(amount)
                guard !total.overflow, total.partialValue <= maximumWork else { throw Failure.quota }
                $0.work = total.partialValue
                if let threshold = cancelAtWork, $0.work >= threshold { $0.cancelled = true }
            }
        }
    }
    func reserveStorage(byteCount: UInt64) throws -> any LogicKernelStorageRetaining {
        try reservation(byteCount: byteCount)
    }
    private func reservation(byteCount: UInt64) throws -> Lease {
        let originalCancelled = original?.isCancelled ?? false
        let ordinal = try state.withLock {
            if originalCancelled { $0.callbacksAfterOriginalCancellation += 1 }
            if $0.cancelled { $0.callbacksAfterCancellation += 1; throw Failure.cancelled }
            let live = $0.live.addingReportingOverflow(byteCount)
            let total = $0.allocations.addingReportingOverflow(byteCount)
            guard !live.overflow, !total.overflow, live.partialValue <= maximumLive else { throw Failure.quota }
            $0.live = live.partialValue; $0.allocations = total.partialValue
            $0.peak = max($0.peak, $0.live); $0.reservations += 1
            if let threshold = cancelAtReservation, $0.reservations == threshold { $0.cancelled = true }
            return $0.reservations
        }
        if let threshold = cancelOriginalAtReservation, ordinal == threshold { original?.cancel() }
        return Lease(owner: self, bytes: byteCount, opens: 0)
    }
    func chargeArtifact(_ work: ArtifactSourceWork) throws {
        try state.withLock {
            if $0.cancelled { $0.callbacksAfterCancellation += 1; throw Failure.cancelled }
            $0.read += work.readBytes; $0.hashed += work.hashedBytes; $0.work += work.workUnits
        }
    }
    func retainArtifact(_ extent: ArtifactSourceExtent) throws -> any ArtifactSourceRetention {
        switch extent {
        case .ownedBytes(let count), .temporaryBytes(let count):
            return try reservation(byteCount: count)
        case .openResources(let count):
            try check(); state.withLock { $0.open += count }
            return Lease(owner: self, bytes: 0, opens: count)
        }
    }
    private final class Lease: LogicKernelStorageRetaining, ArtifactSourceRetention {
        let owner: ControlledReloadTestLedger
        let bytes: UInt64
        let opens: UInt64
        init(owner: ControlledReloadTestLedger, bytes: UInt64, opens: UInt64) {
            self.owner = owner; self.bytes = bytes; self.opens = opens
        }
        deinit { owner.state.withLock { $0.live -= bytes; $0.open -= opens } }
    }
}
