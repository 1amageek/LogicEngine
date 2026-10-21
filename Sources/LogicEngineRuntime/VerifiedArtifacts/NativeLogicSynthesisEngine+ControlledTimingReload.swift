import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import LogicIR
import LogicKernelCore
import STAEngine
import TimingCore

extension NativeLogicSynthesisEngine {
    internal static func controlledTimingReload(_ payload: LogicSynthesisReceipt,
        request: LogicSynthesisRequest, mapped: borrowing MappedGateDesign,
        operating: LogicCheckedOperatingConditions, io: inout LogicRuntimeIO,
        context: inout LogicKernelContext, isolation: isolated (any Actor)? = #isolation) async throws {
        guard let controlled = io.controlled, let constraints = request.constraints.timing,
              let artifact = payload.timingResult, let saved = controlled.savedTiming else {
            throw LogicRuntimeError.unsupported("Missing required STA result")
        }
        let supplies = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
            // STAOperatingSupplyAssumption's existing nonempty guard constructs
            // a five-String scratch array, one assumption at a time.
            let scratch = try inner.reserveStorage(byteCount: UInt64(5 * MemoryLayout<String>.stride))
            let value: [STAOperatingSupplyAssumption]
            do { value = try Self.supplyAssumptions(operating, context: &inner) }
            catch {
                do { try inner.releaseStorage(scratch) }
                catch let cleanup { throw LogicControlledReloadFailure(primary: error, secondary: cleanup) }
                throw error
            }
            try inner.releaseStorage(scratch)
            return value
        }
        defer { withExtendedLifetime(supplies.retention) {} }
        let phase = try LogicReloadPhase.make(context: &context, resources: controlled.resources)
        do {
            let source = try LogicReloadLibertyResources.make(phase: phase)
            let savedData = try io.read(artifact, resources: source)
            let result = saved.value
            let projection = try LogicReloadTimingProjection.build(mapped, top: request.top, resources: source)
            defer { withExtendedLifetime(projection.retention) {} }
            let designData = try TimingJSONEncoding.encode(projection.value,
                formatting: [.sortedKeys, .withoutEscapingSlashes], resources: source)
            defer { withExtendedLifetime(designData) {} }
            let design: TimingArtifactBinding
            do {
                let digest = try Self.controlledTimingDesignDigest(designData.value, resources: source)
                defer { withExtendedLifetime(digest.retention) {} }
                guard let selected = result.inputBindings.first,
                      selected.digest == digest.value, selected.byteCount == UInt64(designData.value.count) else {
                    throw LogicKernelError.invalidInput("STA design differs from actual physical connectivity")
                }
                design = selected
            }
            let requestOwner = try LogicReloadSTARequest.make(request: request, design: design,
                constraints: constraints, supplies: supplies.value, resources: source)
            defer { withExtendedLifetime(requestOwner.retention) {} }
            let sta = requestOwner.value
            let count = sta.libraries.count.addingReportingOverflow(3)
            guard !count.overflow else { throw LibertySourceError.arithmeticOverflow }
            let dictionary = try snapshotBytes(count: count.partialValue, resources: source)
            let scratch = try source.reserveStorage(kind: .temporaryBytes, byteCount: dictionary)
            defer { withExtendedLifetime(scratch) {} }
            var snapshots: [ArtifactID: Data] = [:]
            snapshots.reserveCapacity(count.partialValue)
            snapshots[sta.design.id] = try io.read(Self.logicBinding(sta.design), resources: source)
            for library in sta.libraries {
                try source.check(); try source.chargeWork(1)
                snapshots[library.artifact.id] = try io.read(Self.logicBinding(library.artifact), resources: source)
            }
            snapshots[sta.constraints.id] = try io.read(Self.logicBinding(sta.constraints), resources: source)
            snapshots[sta.pdkManifest.id] = try io.read(Self.logicBinding(sta.pdkManifest), resources: source)
            try LogicReloadTimingValidation.validate(result, request: sta, constraints: constraints, resources: source)
            let reader = InMemoryTimingArtifactReader(artifacts: snapshots)
            let configuration = try LogicReloadTimingIntake.executionResources(reader: reader,
                source: source, limits: io.limits,
                work: context.limits[.workUnits] - context.usage[.workUnits])
            let engine = NativeSTAEngine(reader: reader)
            let prepared = try await engine.prepare(sta, resources: configuration)
            try source.check()
            let replayed = try await engine.execute(prepared)
            try source.check()
            if sta.requireStrictSourceEvidence {
                try await engine.validateSourceEvidence(replayed, against: prepared)
                try source.check()
            }
            try LogicReloadTimingValidation.validate(replayed, request: sta, constraints: constraints, resources: source)
            // Preserve typed equality (including signed-zero semantics), using
            // the owned encoder only to obtain the replay's actual schema size.
            let replaySize = try TimingJSONEncoding.encode(replayed.payload,
                formatting: [.sortedKeys, .withoutEscapingSlashes], resources: source)
            defer { withExtendedLifetime(replaySize) {} }
            let size = UInt64(savedData.count).addingReportingOverflow(UInt64(replaySize.value.count))
            let square = size.partialValue.multipliedReportingOverflow(by: size.partialValue)
            let work = square.partialValue.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !square.overflow, !work.overflow else { throw LibertySourceError.arithmeticOverflow }
            // Each schema atom/UTF-8 byte is bounded by encoded bytes. Across
            // String-keyed dictionaries, all collision probes cost at most B²;
            // arrays/scalars/String comparisons contribute at most B more.
            try source.chargeWork(work.partialValue); try source.check()
            guard replayed.payload == result.payload else {
                throw LogicKernelError.invalidInput("Persisted STA metrics differ from native exact-input replay")
            }
            try source.check()
        } catch {
            do { try phase.importOnce(into: &context) }
            catch let cleanup { throw LogicControlledReloadFailure(primary: controlled.resources.resolved(error), secondary: cleanup) }
            throw controlled.resources.resolved(error)
        }
        try phase.importOnce(into: &context)
        try controlled.resources.checkCaller()
    }

    /// Public lower costs own the actual Data copy and SHA/session payloads.
    internal static func controlledTimingDesignDigestCost(byteCount: UInt64) throws
        -> (temporaryByteCount: UInt64, retainedByteCount: UInt64, workUnits: UInt64) {
        let copy = try SHA256ContentDigester().foundationDataCopyCost(byteCount: byteCount)
        let hash = try SHA256ContentDigester.managedCost(byteCount: byteCount)
        let temporary = copy.temporaryByteCount.addingReportingOverflow(hash.temporaryByteCount)
        let work = copy.workUnits.addingReportingOverflow(hash.workUnits)
        guard !temporary.overflow, !work.overflow else { throw LibertySourceError.arithmeticOverflow }
        return (temporary.partialValue, hash.retainedByteCount, work.partialValue)
    }

    /// Keep the paired reservation with each shared digest through its last use.
    internal static func controlledTimingDesignDigest(_ data: Data,
        resources: any LibertySourceResourceAccounting) throws
        -> (value: ContentDigest, retention: LibertySourceStorageReservation) {
        try resources.check()
        let cost = try controlledTimingDesignDigestCost(byteCount: UInt64(data.count))
        try resources.chargeWork(cost.workUnits)
        try resources.check()
        let scratch = try resources.reserveStorage(kind: .temporaryBytes, byteCount: cost.temporaryByteCount)
        defer { withExtendedLifetime(scratch) {} }
        try resources.check()
        let retained = try resources.reserveStorage(kind: .liveOwnedBytes, byteCount: cost.retainedByteCount)
        try resources.check()
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        try resources.check()
        return (digest, retained)
    }

    private static func snapshotBytes(count: Int, resources: any LibertySourceResourceAccounting) throws -> UInt64 {
        let entries = UInt64(count).multipliedReportingOverflow(by: 4)
        guard !entries.overflow else { throw LibertySourceError.arithmeticOverflow }
        var buckets: UInt64 = 1
        while buckets < entries.partialValue / 3 + 1 {
            try resources.check(); try resources.chargeWork(1)
            let next = buckets.multipliedReportingOverflow(by: 2)
            guard !next.overflow else { throw LibertySourceError.arithmeticOverflow }
            buckets = next.partialValue
        }
        let fields = UInt64(MemoryLayout<ArtifactID>.stride + MemoryLayout<Data>.stride)
        let storage = buckets.multipliedReportingOverflow(by: fields)
        let bits = (buckets / UInt64(UInt.bitWidth) + 1).multipliedReportingOverflow(by: UInt64(MemoryLayout<UInt>.stride))
        let total = storage.partialValue.addingReportingOverflow(bits.partialValue)
        let oldNew = total.partialValue.multipliedReportingOverflow(by: 2)
        guard !storage.overflow, !bits.overflow, !total.overflow, !oldNew.overflow else { throw LibertySourceError.arithmeticOverflow }
        return oldNew.partialValue
    }
}
