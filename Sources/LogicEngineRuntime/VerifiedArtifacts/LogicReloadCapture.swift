import CircuiteFoundation
import CircuiteFoundationFileSystem
import Foundation
import LogicEngineCore
import LogicKernelCore
import PDKDiscovery
import STAEngine
import TimingCore
import Synchronization

/// Captures only the explicit dependency closure; unknown later reads cannot fall back.
internal enum LogicReloadCapture {
    static func capture(_ binding: LogicArtifactBinding, store: any LogicArtifactControlledReading,
        limits: LogicRuntimeLimits, context: inout LogicKernelContext,
        resources: LogicReloadResources, isolation: isolated (any Actor)? = #isolation) async throws -> LogicReloadState {
        try context.requireAccounting(expected: resources)
        var physicalReadBytes: UInt64 = 0
        let receiptRead = try await read(binding, store: store, limits: limits,
            physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
        let receipt = try LogicReloadDocumentDecoding.decode(LogicSynthesisReceipt.self,
            data: receiptRead.value, limits: limits, context: &context, resources: resources,
            validate: LogicReloadCodingAudit.receipt)
        let captureMetadata = try LogicReloadKernelPhase.run(context: &context, resources: resources) { inner in
            _ = try inner.reserveStorage(byteCount: UInt64(MemoryLayout<LogicControlledReloadFailure>.stride))
            return true
        }
        var partialRequest: PDKDecodedDocument<LogicSynthesisRequest>?
        do {
            let requestRead = try await read(receipt.value.request, store: store, limits: limits,
                physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
            let request = try LogicReloadDocumentDecoding.decode(LogicSynthesisRequest.self,
                data: requestRead.value, limits: limits, context: &context, resources: resources,
                validate: LogicReloadCodingAudit.request)
            partialRequest = request
            try LogicReloadRequestValidation.validate(request.value, context: &context)
            let savedTiming: TimingTransformValue<STAExecutionResult>?
            let timingRead: (value: Data, retention: LogicArtifactReadRetention)?
            if request.value.constraints.timing != nil, let artifact = receipt.value.timingResult {
                let bytes = try await read(artifact, store: store, limits: limits,
                    physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
                timingRead = bytes
                savedTiming = try LogicReloadTimingIntake.decodeSaved(bytes.value, limits: limits,
                    context: &context, resources: resources)
            } else { timingRead = nil; savedTiming = nil }
            var capacity = 9
            try add(request.value.sources.count, to: &capacity)
            if let scope = request.value.operatingProcessScope {
                try add(scope.libraries.count, to: &capacity); try add(1, to: &capacity)
            }
            if let timing = request.value.constraints.timing {
                try add(timing.libraries.count, to: &capacity); try add(2, to: &capacity)
            }
            let byteCount = UInt64(capacity).multipliedReportingOverflow(
                by: UInt64(MemoryLayout<LogicReloadSnapshot.Entry>.stride))
            guard !byteCount.overflow else { throw LogicKernelError.invalidInput("Reload snapshot capacity overflows") }
            let metadataScope = try context.beginRetentionScope()
            let snapshot: LogicReloadSnapshot
            let metadata: LogicKernelRetention
            do {
                let snapshotHeader = UInt64(2 * MemoryLayout<UInt>.stride
                    + MemoryLayout<[LogicReloadSnapshot.Entry]>.stride + MemoryLayout<LogicKernelRetention>.stride)
                let stateHeader = UInt64(2 * MemoryLayout<UInt>.stride
                    + MemoryLayout<LogicReloadSnapshot>.stride + MemoryLayout<LogicReloadResources>.stride
                    + MemoryLayout<PDKDecodedDocument<LogicSynthesisReceipt>>.stride
                    + MemoryLayout<PDKDecodedDocument<LogicSynthesisRequest>>.stride
                    + MemoryLayout<LogicKernelRetention>.stride + MemoryLayout<UInt64>.stride
                    + MemoryLayout<TimingTransformValue<STAExecutionResult>?>.stride
                    + MemoryLayout<Mutex<LogicReloadRetainedParts>>.stride)
                let headers = snapshotHeader.addingReportingOverflow(stateHeader)
                let total = byteCount.partialValue.addingReportingOverflow(headers.partialValue)
                guard !headers.overflow, !total.overflow else { throw LogicKernelError.invalidInput("Reload owner metadata overflows") }
                _ = try context.reserveStorage(byteCount: total.partialValue)
                var entries: [LogicReloadSnapshot.Entry] = []
                entries.reserveCapacity(capacity)
                entries.append(.init(binding: binding, data: receiptRead.value, retention: receiptRead.retention))
                entries.append(.init(binding: receipt.value.request, data: requestRead.value, retention: requestRead.retention))
                for source in request.value.sources {
                    try await append(source.artifact, to: &entries, store: store, limits: limits,
                        physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
                }
                try await append(request.value.library, to: &entries, store: store, limits: limits,
                    physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
                try await append(receipt.value.originalBitDesign, to: &entries, store: store, limits: limits,
                    physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
                try await append(receipt.value.mappedIdentities, to: &entries, store: store, limits: limits,
                    physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
                try await append(receipt.value.netlist, to: &entries, store: store, limits: limits,
                    physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
                try await append(receipt.value.proof, to: &entries, store: store, limits: limits,
                    physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
                if let timingRead, let artifact = receipt.value.timingResult {
                    entries.append(.init(binding: artifact, data: timingRead.value, retention: timingRead.retention))
                }
                if let design = savedTiming?.value.inputBindings.first {
                    try await append(NativeLogicSynthesisEngine.logicBinding(design), to: &entries,
                        store: store, limits: limits, physicalReadBytes: &physicalReadBytes,
                        context: &context, resources: resources)
                }
                if let scope = request.value.operatingProcessScope {
                    for library in scope.libraries {
                        try await append(NativeLogicSynthesisEngine.logicBinding(library.artifact), to: &entries,
                            store: store, limits: limits, physicalReadBytes: &physicalReadBytes,
                            context: &context, resources: resources)
                    }
                    try await append(NativeLogicSynthesisEngine.logicBinding(scope.pdkManifest), to: &entries,
                        store: store, limits: limits, physicalReadBytes: &physicalReadBytes,
                        context: &context, resources: resources)
                }
                if let timing = request.value.constraints.timing {
                    for library in timing.libraries {
                        try await append(NativeLogicSynthesisEngine.logicBinding(library.artifact), to: &entries,
                            store: store, limits: limits, physicalReadBytes: &physicalReadBytes,
                            context: &context, resources: resources)
                    }
                    try await append(NativeLogicSynthesisEngine.logicBinding(timing.pdkManifest), to: &entries,
                        store: store, limits: limits, physicalReadBytes: &physicalReadBytes,
                        context: &context, resources: resources)
                    try await append(NativeLogicSynthesisEngine.logicBinding(timing.constraints), to: &entries,
                        store: store, limits: limits, physicalReadBytes: &physicalReadBytes,
                        context: &context, resources: resources)
                }
                try resources.checkCaller()
                metadata = try context.finishRetentionScope(metadataScope)
                snapshot = .init(entries: entries, metadata: metadata)
            } catch {
                do { try context.discardRetentionScope(metadataScope) }
                catch let cleanup { throw LogicControlledReloadFailure(primary: resources.resolved(error), secondary: cleanup) }
                throw resources.resolved(error)
            }
            // Snapshot-entry headers are phase scratch. The successful value keeps only
            // its own fixed owner metadata, never the entry-table lease.
            let resultMetadata = try LogicReloadKernelPhase.run(context: &context, resources: resources) { context in
                _ = try context.reserveStorage(byteCount: UInt64(MemoryLayout<LogicReloadRetention>.stride))
                return true
            }
            return .init(snapshot: snapshot, resources: resources, receipt: receipt, request: request,
                metadata: resultMetadata.retention, receiptByteCount: binding.byteCount, savedTiming: savedTiming)
        } catch {
            throw LogicControlledReloadFailure(primary: resources.resolved(error),
                retention: captureMetadata.retention, documentRetention: (receipt, partialRequest))
        }
    }

    private static func append(_ binding: LogicArtifactBinding, to entries: inout [LogicReloadSnapshot.Entry],
        store: any LogicArtifactControlledReading, limits: LogicRuntimeLimits,
        physicalReadBytes: inout UInt64, context: inout LogicKernelContext,
        resources: LogicReloadResources, isolation: isolated (any Actor)? = #isolation) async throws {
        for entry in entries {
            if try LogicReloadComparison.binding(entry.binding, binding, context: &context) { return }
        }
        let result = try await read(binding, store: store, limits: limits,
            physicalReadBytes: &physicalReadBytes, context: &context, resources: resources)
        entries.append(.init(binding: binding, data: result.value, retention: result.retention))
    }

    private static func read(_ binding: LogicArtifactBinding, store: any LogicArtifactControlledReading,
        limits: LogicRuntimeLimits, physicalReadBytes: inout UInt64,
        context: inout LogicKernelContext, resources: LogicReloadResources, isolation: isolated (any Actor)? = #isolation) async throws
        -> (value: Data, retention: LogicArtifactReadRetention) {
        let next = physicalReadBytes.addingReportingOverflow(binding.byteCount)
        guard !next.overflow, next.partialValue <= limits.maximumInputBytes else {
            throw LogicKernelError.resourceLimit(resource: .expansion, limit: limits.maximumInputBytes, requested: nil)
        }
        physicalReadBytes = next.partialValue
        let total = max(binding.byteCount, 1)
        let page = min(total, 65_536)
        let pages = total / page + (total.isMultiple(of: page) ? 0 : 1)
        let remainingWork = context.limits[.workUnits] - context.usage[.workUnits]
        guard remainingWork > 0 else {
            throw LogicKernelError.resourceLimit(resource: .workUnits, limit: context.limits[.workUnits], requested: nil)
        }
        let budget = try ArtifactAccessBudget(maximumPageByteCount: page, maximumTotalByteCount: total,
            maximumPageCount: pages, maximumWorkUnitCount: remainingWork,
            maximumDurationNanoseconds: limits.timeoutNanoseconds)
        let phase = try LogicReloadPhase.make(context: &context, resources: resources)
        let result: (value: Data, retention: LogicArtifactReadRetention)
        do {
            let control = try LogicReloadArtifactResources.make(phase: phase)
            result = try await store.readControlled(binding, budget: budget, control: control)
        }
        catch {
            do { try phase.importOnce(into: &context) }
            catch let cleanup { throw LogicControlledReloadFailure(primary: resources.resolved(error), secondary: cleanup) }
            throw resources.resolved(error)
        }
        try phase.importOnce(into: &context)
        try resources.checkCaller()
        return result
    }

    private static func add(_ count: Int, to value: inout Int) throws(LogicKernelError) {
        let result = value.addingReportingOverflow(count)
        guard count >= 0, !result.overflow else { throw .invalidInput("Reload dependency capacity overflows") }
        value = result.partialValue
    }
}
