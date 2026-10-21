import CircuiteFoundationFileSystem
import LogicKernelCore
import Synchronization

/// Install this exact invocation adapter in the caller's kernel context.
public final class LogicReloadResources: LogicKernelAccounting, ArtifactSourceControl {
    private let control: any LogicReloadResourceControlling
    private let firstFailure = Mutex<(any Error)?>(nil)

    public init(control: any LogicReloadResourceControlling) {
        self.control = control
    }

    internal var externalFailure: (any Error)? {
        firstFailure.withLock { $0 }
    }

    internal func checkCaller() throws {
        if let failure = externalFailure { throw failure }
        do {
            try Task.checkCancellation()
            try control.check()
            try Task.checkCancellation()
        } catch {
            record(error)
            throw error
        }
        if let failure = externalFailure { throw failure }
    }

    public func observeBitWidth(_ width: UInt64) throws(LogicKernelError) {
        do {
            try checkCaller()
            try control.observeBitWidth(width)
            try checkCaller()
        } catch {
            record(error)
            throw .externalAccountingFailure
        }
    }

    public func charge(_ resource: LogicResource, amount: UInt64) throws(LogicKernelError) {
        do {
            try checkCaller()
            try control.charge(resource, amount: amount)
            try checkCaller()
        } catch {
            record(error)
            throw .externalAccountingFailure
        }
    }

    public func reserveStorage(byteCount: UInt64)
        throws(LogicKernelError) -> any LogicKernelStorageRetaining {
        do {
            try checkCaller()
            let reservation = try control.reserveStorage(byteCount: byteCount)
            try checkCaller()
            return reservation
        } catch {
            // A reservation returned before post-callback cancellation drops here.
            record(error)
            throw .externalAccountingFailure
        }
    }

    public func check() throws(ArtifactSourceControlError) {
        do { try checkCaller() }
        catch {
            record(error)
            throw Self.controlFailure
        }
    }

    public func charge(_ work: ArtifactSourceWork) throws(ArtifactSourceControlError) {
        do {
            try checkCaller()
            try control.chargeArtifact(work)
            try checkCaller()
        } catch {
            record(error)
            throw Self.controlFailure
        }
    }

    public func retain(_ extent: ArtifactSourceExtent)
        throws(ArtifactSourceControlError) -> any ArtifactSourceRetention {
        do {
            try checkCaller()
            let reservation = try control.retainArtifact(extent)
            try checkCaller()
            return reservation
        } catch {
            record(error)
            throw Self.controlFailure
        }
    }

    /// Keep the whole lower failure: its private storage anchor is not its cause.
    internal func resolved(_ error: any Error) -> any Error {
        guard let primary = externalFailure else { return error }
        return LogicControlledReloadFailure(primary: primary, secondary: error)
    }

    internal func record(_ error: any Error) {
        firstFailure.withLock {
            if $0 == nil { $0 = error }
        }
    }

    internal func phaseCharge(_ resource: LogicResource, amount: UInt64,
                              commit: () -> Void) throws {
        try checkCaller()
        try control.charge(resource, amount: amount)
        commit()
        try checkCaller()
    }

    internal func phaseReserve(byteCount: UInt64, commit: () -> Void) throws
        -> any LogicKernelStorageRetaining {
        try checkCaller()
        let reservation = try control.reserveStorage(byteCount: byteCount)
        commit()
        try checkCaller()
        return reservation
    }

    internal func phaseArtifactCharge(_ work: ArtifactSourceWork) throws {
        try checkCaller()
        try control.chargeArtifact(work)
        try checkCaller()
    }

    private static var controlFailure: ArtifactSourceControlError {
        .unsupportedCapability(reason: "Caller accounting failed; original cause retained by invocation.")
    }
}
