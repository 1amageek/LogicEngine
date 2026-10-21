import CircuiteFoundationFileSystem
import LogicKernelCore

internal final class LogicReloadArtifactResources: ArtifactSourceControl {
    let phase: LogicReloadPhase
    private let metadata: any LogicKernelStorageRetaining
    static func make(phase: LogicReloadPhase) throws -> LogicReloadArtifactResources {
        let bytes = UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<LogicReloadPhase>.stride
            + MemoryLayout<any LogicKernelStorageRetaining>.stride)
        let metadata = try phase.reserveStorage(bytes)
        try phase.check()
        return .init(phase: phase, metadata: metadata)
    }
    private init(phase: LogicReloadPhase, metadata: any LogicKernelStorageRetaining) {
        self.phase = phase; self.metadata = metadata
    }

    func check() throws(ArtifactSourceControlError) {
        do { try phase.check() }
        catch { throw preserve(error) }
    }

    func charge(_ work: ArtifactSourceWork) throws(ArtifactSourceControlError) {
        do {
            // Kernel import owns work once; the host callback retains actual I/O dimensions.
            try phase.chargeWork(work.workUnits)
            try phase.resources.phaseArtifactCharge(.init(readBytes: work.readBytes,
                hashedBytes: work.hashedBytes, pages: work.pages, visitedEntries: work.visitedEntries))
            try phase.check()
        } catch { throw preserve(error) }
    }

    func retain(_ extent: ArtifactSourceExtent)
        throws(ArtifactSourceControlError) -> any ArtifactSourceRetention {
        do {
            try phase.check()
            let reservation: any ArtifactSourceRetention
            switch extent {
            case .ownedBytes(let count), .temporaryBytes(let count):
                let metadata = UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<any LogicKernelStorageRetaining>.stride)
                let total = count.addingReportingOverflow(metadata)
                guard !total.overflow else { throw LogicKernelError.invalidInput("Artifact retention metadata overflows") }
                reservation = Storage(lease: try phase.reserveStorage(total.partialValue))
            case .openResources:
                reservation = try phase.resources.retain(extent)
            }
            try phase.check()
            return reservation
        } catch { throw preserve(error) }
    }

    private func preserve(_ error: any Error) -> ArtifactSourceControlError {
        phase.resources.record(error)
        return .unsupportedCapability(reason: "Caller accounting failed; original cause retained by invocation.")
    }

    private final class Storage: ArtifactSourceRetention {
        let lease: any LogicKernelStorageRetaining
        init(lease: any LogicKernelStorageRetaining) { self.lease = lease }
    }
}
