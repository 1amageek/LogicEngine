import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import LogicEngineCore
import LogicKernelCore
import TimingCore

internal struct LogicRuntimeIO {
    let store: any LogicArtifactStoring
    let limits: LogicRuntimeLimits
    let control: any LogicRunControlling
    var controlled: LogicReloadState? = nil
    var readBytes: UInt64 = 0
    var writtenBytes: UInt64 = 0
    var verifiedReadBindings: Set<LogicArtifactBinding>? = nil

    mutating func read(_ binding: LogicArtifactBinding) throws -> Data {
        guard controlled == nil else {
            throw LogicKernelError.unsupported("Controlled reload requires its context-bound snapshot read")
        }
        try control.checkpoint()
        try admitRead(binding.byteCount)
        let data = try readAdmitted(binding)
        verifiedReadBindings?.insert(binding)
        return data
    }
    mutating func read(_ binding: LogicArtifactBinding, context: inout LogicKernelContext) throws -> Data {
        guard let controlled else { return try read(binding) }
        try context.checkpoint()
        try controlled.resources.checkCaller()
        try admitRead(binding.byteCount)
        let data = try controlled.snapshot.read(binding, context: &context)
        try controlled.resources.checkCaller()
        return data
    }

    mutating func read(_ binding: LogicArtifactBinding, resources: any LibertySourceResourceAccounting) throws -> Data {
        guard let controlled else { throw LogicKernelError.invalidInput("Missing controlled reload state") }
        try resources.check()
        try admitRead(binding.byteCount)
        let data = try controlled.snapshot.read(binding, resources: resources)
        try resources.check()
        return data
    }

    private mutating func admitRead(_ count: UInt64) throws {
        let total = readBytes.addingReportingOverflow(count)
        guard !total.overflow, total.partialValue <= limits.maximumInputBytes else {
            throw LogicKernelError.resourceLimit(resource: .expansion, limit: limits.maximumInputBytes, requested: nil)
        }
        readBytes = total.partialValue
    }
    private func readAdmitted(_ binding: LogicArtifactBinding) throws -> Data {
        let data = try store.read(binding)
        try verify(data, reference: binding.reference)
        try control.checkpoint()
        return data
    }
    func verify(_ data: Data, reference: ArtifactReference) throws {
        guard UInt64(data.count) == reference.byteCount else { throw LogicExecutionError.artifactByteCountMismatch(reference.id.description) }
        guard try SHA256ContentDigester().digest(data: data, using: .sha256) == reference.digest else {
            throw LogicExecutionError.artifactDigestMismatch(reference.id.description)
        }
    }
    mutating func write(_ data: Data, name: String, kind: ArtifactKind, format: ArtifactFormat,
                        request: LogicSynthesisRequest) throws -> LogicArtifactBinding {
        try write(data, name: name, kind: kind, format: format, runID: request.runID, directory: request.artifactDirectory)
    }
    mutating func write(_ data: Data, name: String, kind: ArtifactKind, format: ArtifactFormat,
                        runID: String, directory: String?) throws -> LogicArtifactBinding {
        try control.checkpoint()
        let total = writtenBytes.addingReportingOverflow(UInt64(data.count))
        guard !total.overflow, total.partialValue <= limits.maximumOutputBytes else {
            throw LogicKernelError.resourceLimit(resource: .outputBytes, limit: limits.maximumOutputBytes, requested: nil)
        }
        try admitRead(UInt64(data.count))
        writtenBytes = total.partialValue
        let result = try store.write(data, fileName: name, outputDirectory: directory,
                                     runID: runID, kind: kind, format: format)
        try verify(data, reference: result.reference)
        _ = try readAdmitted(result)
        return result
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
