import CircuiteFoundationFileSystem
import LogicKernelCore

/// One caller-owned policy for the complete reload invocation.
public protocol LogicReloadResourceControlling: Sendable {
    func check() throws
    func observeBitWidth(_ width: UInt64) throws
    func charge(_ resource: LogicResource, amount: UInt64) throws
    func reserveStorage(byteCount: UInt64) throws -> any LogicKernelStorageRetaining
    func chargeArtifact(_ work: ArtifactSourceWork) throws
    func retainArtifact(_ extent: ArtifactSourceExtent) throws -> any ArtifactSourceRetention
}
