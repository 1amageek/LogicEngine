import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import Foundation

extension FileSystemLogicArtifactStore: LogicArtifactControlledReading {
    public func readControlled(
        _ artifact: LogicArtifactBinding,
        budget: ArtifactAccessBudget,
        control: any ArtifactSourceControl
    ) async throws -> (value: Data, retention: LogicArtifactReadRetention) {
        try control.check()
        guard artifact.byteCount <= budget.maximumTotalByteCount,
              artifact.byteCount <= UInt64(Int.max) else {
            throw ArtifactSourceDiscoveryError.access(.totalByteLimitExceeded(
                limit: min(budget.maximumTotalByteCount, UInt64(Int.max)), requested: artifact.byteCount))
        }
        var pathReservation: (any ArtifactSourceRetention)?
        defer { withExtendedLifetime(pathReservation) {} }
        let rootID: ArtifactRootID
        let relativePath: ArtifactRelativePath
        let directory: URL
        switch artifact.availability {
        case .local(let identity, let selectedRoot, let path):
            guard identity == artifact.id else {
                throw LogicExecutionError.artifactDigestMismatch("Controlled artifact reference")
            }
            switch selectedRoot.rawValue {
            case LogicArtifactBinding.workspaceRootIdentifier:
                rootID = selectedRoot; relativePath = path; directory = rootDirectory
            case LogicArtifactBinding.outputRootIdentifier:
                guard let output = defaultOutputDirectory else {
                    throw LogicExecutionError.artifactReadOutsideRoot("Controlled artifact availability")
                }
                rootID = selectedRoot; relativePath = path; directory = output
            case LogicArtifactBinding.localFileSystemRootIdentifier:
                let grant = try absoluteGrant(path, control: control)
                let prefix = grant.prefix
                directory = grant.directory
                rootID = grant.rootID
                let count = path.segments.count - prefix.count
                let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(MemoryLayout<String>.stride))
                guard !bytes.overflow else { throw ArtifactSourceControlError.arithmeticOverflow(resource: .temporaryBytes) }
                pathReservation = try control.retain(.temporaryBytes(bytes.partialValue))
                try control.check()
                var segments: [String] = []
                segments.reserveCapacity(count)
                for index in prefix.count..<path.segments.count {
                    try control.charge(.init(workUnits: 1))
                    try control.check()
                    segments.append(path.segments[index])
                }
                relativePath = try ArtifactRelativePath(segments: segments)
            default:
                var selected: LogicArtifactReadRoot?
                for grant in controlledReadRoots {
                    let left = UInt64(grant.rootID.rawValue.utf8.count), right = UInt64(selectedRoot.rawValue.utf8.count)
                    let total = left.addingReportingOverflow(right)
                    guard !total.overflow else { throw ArtifactSourceControlError.arithmeticOverflow(resource: .temporaryBytes) }
                    try control.charge(.init(workUnits: total.partialValue)); try control.check()
                    if grant.rootID == selectedRoot { selected = grant; break }
                }
                guard let selected else { throw LogicExecutionError.artifactReadOutsideRoot("Controlled artifact availability") }
                rootID = selected.rootID; relativePath = path; directory = selected.directoryURL
            }
        case .service:
            throw LogicExecutionError.artifactReadOutsideRoot("Controlled artifact availability")
        }

        let failureMetadata = try control.retain(.ownedBytes(UInt64(MemoryLayout<LogicArtifactControlledReadFailure>.stride)))
        try control.check()
        let rootReservation = try control.retain(.openResources(1))
        defer { withExtendedLifetime(rootReservation) {} }
        try control.check()
        let root = try ArtifactRootCapability(rootID: rootID, directoryURL: directory,
                                              digester: SHA256ContentDigester())
        let source: ArtifactDiscoveredSource
        do {
            source = try await root.discover(.init(rootID: rootID, relativePath: relativePath,
                descriptor: artifact.reference.descriptor, budget: budget), control: control)
        } catch {
            // Closing owns its own task and must finish even when the caller is cancelled.
            let termination = await root.close()
            do { try await termination.wait() }
            catch let cleanup { throw LogicArtifactControlledReadFailure(primary: error, cleanup: cleanup,
                                                                        retention: rootReservation, metadata: failureMetadata) }
            throw LogicArtifactControlledReadFailure(primary: error,
                retention: rootReservation, metadata: failureMetadata)
        }
        let termination = await root.close()
        do { try await termination.wait() }
        catch { throw LogicArtifactControlledReadFailure(primary: error, retention: rootReservation, metadata: failureMetadata) }
        try control.check()
        guard source.reference == artifact.reference else {
            if source.reference.byteCount != artifact.byteCount {
                throw LogicExecutionError.artifactByteCountMismatch("Controlled artifact reference")
            }
            throw LogicExecutionError.artifactDigestMismatch("Controlled artifact reference")
        }

        // The original controlled pages coexist with this required Foundation boundary copy.
        let metadata = UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<any ArtifactSourceRetention>.stride)
        let bytes = source.byteCount.addingReportingOverflow(metadata)
        guard !bytes.overflow else { throw ArtifactSourceControlError.arithmeticOverflow(resource: .ownedBytes) }
        let reservation = try control.retain(.ownedBytes(bytes.partialValue))
        try control.check()
        try control.charge(.init(workUnits: source.byteCount))
        try control.check()
        let data = try source.withAccountedUnsafeBytes { bytes in Data(bytes) }
        try control.check()
        return (data, LogicArtifactReadRetention(reservation: reservation))
    }

    private func absoluteGrant(_ path: ArtifactRelativePath, control: any ArtifactSourceControl) throws
        -> (rootID: ArtifactRootID, directory: URL, prefix: [String]) {
        if try Self.matches(controlledWorkspaceSegments, in: path, control: control) {
            return (try .init(rawValue: LogicArtifactBinding.workspaceRootIdentifier), rootDirectory, controlledWorkspaceSegments)
        }
        if let directory = defaultOutputDirectory, let segments = controlledOutputSegments,
           try Self.matches(segments, in: path, control: control) {
            return (try .init(rawValue: LogicArtifactBinding.outputRootIdentifier), directory, segments)
        }
        for grant in controlledReadRoots {
            if try Self.matches(grant.segments, in: path, control: control) {
                return (grant.rootID, grant.directoryURL, grant.segments)
            }
        }
        throw LogicExecutionError.artifactReadOutsideRoot("Controlled absolute availability")
    }

    private static func matches(_ prefix: [String], in path: ArtifactRelativePath,
                                control: any ArtifactSourceControl) throws -> Bool {
        guard path.segments.count > prefix.count else { return false }
        for index in prefix.indices {
            let left = prefix[index], right = path.segments[index]
            let bytes = UInt64(left.utf8.count).addingReportingOverflow(UInt64(right.utf8.count))
            let work = bytes.partialValue.addingReportingOverflow(1)
            guard !bytes.overflow, !work.overflow else {
                throw ArtifactSourceControlError.arithmeticOverflow(resource: .temporaryBytes)
            }
            try control.charge(.init(workUnits: work.partialValue))
            try control.check()
            guard left.utf8.elementsEqual(right.utf8) else { return false }
        }
        return true
    }
}
