import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import Foundation
import LogicEngineCore
import LogicEngineRuntime
import LogicKernelCore
import LogicProof
import PDKDiscovery
import STAEngine
import Testing

@Suite(.timeLimit(.minutes(2)))
struct ControlledReloadTests {
    struct Control: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) {}
    }
    private func context(_ limits: LogicRuntimeLimits, _ resources: LogicReloadResources) throws -> LogicKernelContext {
        .init(limits: try limits.kernelLimits(), control: Control(), accounting: resources)
    }
    private func marker(_ error: any Error) -> ControlledReloadTestLedger.Failure? {
        if let direct = error as? ControlledReloadTestLedger.Failure { return direct }
        if let wrapper = error as? LogicControlledReloadFailure { return marker(wrapper.primary) }
        return nil
    }
    @Test func originalProofReplayUsesPrespentContextAndLastCopiedAnchor() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let produced = try await engine.execute(request)
        let ledger = ControlledReloadTestLedger(), resources = LogicReloadResources(control: ledger)
        var run = try context(request.limits, resources)
        try run.charge(.workUnits, amount: 17)
        var anchor: LogicReloadRetention?
        do {
            let loaded = try await engine.load(produced.receipt, limits: request.limits, context: &run, resources: resources)
            try loaded.value.equivalence.requireBinding(to: loaded.value.problem)
            #expect(loaded.value.receipt == produced.payload)
            #expect(loaded.value.mapped.instanceCount == 8)
            #expect(run.usage[.workUnits] > 17)
            #expect(ledger.snapshot.work == run.usage[.workUnits])
            #expect(ledger.snapshot.read > 0 && ledger.snapshot.hashed > 0)
            anchor = loaded.retention
        }
        var copy = anchor
        anchor = nil
        #expect(ledger.snapshot.live > 0)
        withExtendedLifetime(copy) {}
        copy = nil
        #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
    }
    @Test func mandatoryOriginalSTAIsActuallyRepreparedAndReplayed() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try ActualCellTimingTests().request(root: root)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: store)
        let produced = try await engine.execute(request)
        let ordinary = try JSONDecoder().decode(STAExecutionResult.self,
            from: store.read(#require(produced.payload.timingResult)))
        let canonical = try STAExecutionLimits()
        #expect(request.limits.maximumTableEntries == 500)
        #expect(ordinary.payload.effectiveConfiguration?.maximumPathStates == canonical.maximumPathStates)
        #expect(ordinary.payload.effectiveConfiguration?.maximumPathWorkUnits == canonical.maximumPathWorkUnits)
        let ledger = ControlledReloadTestLedger(), resources = LogicReloadResources(control: ledger)
        var run = try context(request.limits, resources)
        try run.charge(.workUnits, amount: 17)
        do {
            let loaded = try await engine.load(produced.receipt, limits: request.limits, context: &run, resources: resources)
            try loaded.value.equivalence.requireBinding(to: loaded.value.problem)
            #expect(loaded.value.receipt.timingResult == produced.payload.timingResult)
            #expect(loaded.value.request.constraints.timing != nil)
            #expect(run.usage[.workUnits] > 17)
            #expect(ledger.snapshot.work == run.usage[.workUnits])
            withExtendedLifetime(loaded.retention) {}
        }
        #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
    }
    @Test(arguments: [UInt64(1), 8])
    func postReservationCancellationPreservesCauseAndStopsCallbacks(_ reservation: UInt64) async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let produced = try await engine.execute(request)
        let ledger = ControlledReloadTestLedger(cancelAtReservation: reservation)
        let resources = LogicReloadResources(control: ledger)
        var run = try context(request.limits, resources)
        do {
            _ = try await engine.load(produced.receipt, limits: request.limits, context: &run, resources: resources)
            Issue.record("Cancelled controlled reload published a value")
        } catch { #expect(marker(error) == .cancelled) }
        #expect(ledger.snapshot.callbacksAfterCancellation == 0)
        #expect(ledger.snapshot.reservations == reservation)
        #expect(ledger.snapshot.allocations > 0)
        #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
    }
    @Test(arguments: [UInt64(1), 20])
    func originalControlCancellationSurvivesASeparateLiveB(_ reservation: UInt64) async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let produced = try await engine.execute(request)
        let original = ControlledReloadTestControl()
        let ledger = ControlledReloadTestLedger(original: original, cancelOriginalAtReservation: reservation)
        let resources = LogicReloadResources(control: ledger)
        var run = LogicKernelContext(limits: try request.limits.kernelLimits(), control: original, accounting: resources)
        do {
            _ = try await engine.load(produced.receipt, limits: request.limits, context: &run, resources: resources)
            Issue.record("Original-control cancellation published a value")
        } catch let failure as LogicControlledReloadFailure {
            #expect(failure.primary as? LogicKernelError == .cancelled)
        } catch let failure as LogicKernelError { #expect(failure == .cancelled) }
        #expect(original.isCancelled && !ledger.snapshot.cancelled)
        #expect(ledger.snapshot.callbacksAfterOriginalCancellation == 0)
        #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
    }
    @Test func workCancellationAndTinyQuotaRemainOriginalFailures() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let produced = try await engine.execute(request)
        for ledger in [ControlledReloadTestLedger(cancelAtWork: 256), ControlledReloadTestLedger(maximumLive: 32)] {
            let resources = LogicReloadResources(control: ledger)
            var run = try context(request.limits, resources)
            do {
                _ = try await engine.load(produced.receipt, limits: request.limits, context: &run, resources: resources)
                Issue.record("Refused controlled reload published a value")
            } catch { #expect(marker(error) == (ledger.snapshot.cancelled ? .cancelled : .quota)) }
            #expect(ledger.snapshot.callbacksAfterCancellation == 0)
            #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
        }
    }
    @Test func wrongInstalledAccountantIsRefusedBeforeAnyRead() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let produced = try await engine.execute(request)
        let installedLedger = ControlledReloadTestLedger(), foreignLedger = ControlledReloadTestLedger()
        let installed = LogicReloadResources(control: installedLedger), foreign = LogicReloadResources(control: foreignLedger)
        var run = try context(request.limits, installed)
        await #expect(throws: LogicKernelError.self) {
            try await engine.load(produced.receipt, limits: request.limits, context: &run, resources: foreign)
        }
        #expect(installedLedger.snapshot.read == 0 && foreignLedger.snapshot.read == 0)
        #expect(installedLedger.snapshot.live == 0 && foreignLedger.snapshot.live == 0)
    }
    @Test func canonicalRUPParityUnknownFieldsAndAmbiguousJSONProfile() throws {
        let limits = ActualCellRuntimeTests().limits()
        var construction = LogicKernelContext(limits: try limits.kernelLimits(), control: Control())
        var formula = try LogicCNFBuilder(variableCount: 1, clauseCapacity: 2, literalCapacity: 2, context: &construction)
        try formula.appendClause([LogicSATLiteral(1)], context: &construction)
        try formula.appendClause([LogicSATLiteral(-1)], context: &construction)
        let cnf = try formula.finish(context: &construction)
        var builder = try LogicRUPBuilder(formula: cnf, clauseCapacity: 1, literalCapacity: 0, context: &construction)
        try builder.appendClause([], context: &construction)
        let certificate = try builder.finish(context: &construction)
        let codec = LogicRUPCertificateCodec()
        let canonical = try codec.encode(certificate)
        let ledger = ControlledReloadTestLedger(), resources = LogicReloadResources(control: ledger)
        var run = try context(limits, resources)
        do {
            let encoded = try codec.encodeControlled(certificate, context: &run, resources: resources)
            #expect(encoded.value == canonical)
            let decoded = try codec.decodeControlled(canonical, limits: limits, context: &run, resources: resources)
            _ = try NativeLogicRUPChecker().check(decoded.value.formula, certificate: decoded.value, context: &construction)
            withExtendedLifetime((encoded.retention, decoded.retention)) {}
        }
        #expect(ledger.snapshot.live == 0)
        let unknown = Data("{\"additions\":[[]],\"clauses\":[[1],[-1]],\"schemaVersion\":1,\"variables\":1,\"unknown\":true}".utf8)
        do {
            let decoded = try codec.decodeControlled(unknown, limits: limits, context: &run, resources: resources)
            #expect(decoded.value.formula.clauseCount == 2)
            withExtendedLifetime(decoded.retention) {}
        }
        for malformed in [Data("{\"schemaVersion\":1,\"schemaVersion\":1,\"variables\":1,\"clauses\":[[1],[-1]],\"additions\":[[]]}".utf8),
                          try #require(String(decoding: canonical, as: UTF8.self).data(using: .utf16))] {
            do {
                _ = try codec.decodeControlled(malformed, limits: limits, context: &run, resources: resources)
                Issue.record("Ambiguous or non-UTF8 controlled JSON was accepted")
            } catch let failure as PDKControlledDecodeFailure {
                switch failure.cause {
                case .duplicateKey, .invalidUTF8, .malformed: break
                default: Issue.record("Unexpected controlled profile cause: \(failure.cause)")
                }
            }
        }
        #expect(ledger.snapshot.live == 0)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ControlledArtifactReadTests {
    @Test func additionalRootIsExplicitAndReturnedDataKeepsItsLastAnchor() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary(), external = try helper.temporary()
        defer {
            do { try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: external) }
            catch { Issue.record(error) }
        }
        let bytes = Data("exact external artifact".utf8)
        let binding = try helper.input(bytes, name: "outside.json", format: .json, root: external)
        let grant = try LogicArtifactReadRoot(rootID: .init(rawValue: "pdk-read-grant"), directoryURL: external)
        let store = try FileSystemLogicArtifactStore(rootDirectory: root, controlledReadRoots: [grant])
        let denied = FileSystemLogicArtifactStore(rootDirectory: root)
        let ledger = ControlledReloadTestLedger(), resources = LogicReloadResources(control: ledger)
        let budget = try ArtifactAccessBudget(maximumPageByteCount: 4, maximumTotalByteCount: 128,
            maximumPageCount: 32, maximumWorkUnitCount: 1_000_000, maximumDurationNanoseconds: 5_000_000_000)
        await #expect(throws: LogicExecutionError.self) {
            try await denied.readControlled(binding, budget: budget, control: resources)
        }
        var anchor: LogicArtifactReadRetention?
        do {
            let read = try await store.readControlled(binding, budget: budget, control: resources)
            #expect(read.value == bytes)
            #expect(ledger.snapshot.open == 0)
            anchor = read.retention
        }
        var copy = anchor
        anchor = nil
        #expect(ledger.snapshot.live > 0)
        withExtendedLifetime(copy) {}
        copy = nil
        #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
        #expect(throws: LogicArtifactReadRootError.duplicateRootID(grant.rootID)) {
            try FileSystemLogicArtifactStore(rootDirectory: root, controlledReadRoots: [grant, grant])
        }
        let reserved = try ArtifactRootID(rawValue: LogicArtifactBinding.workspaceRootIdentifier)
        #expect(throws: LogicArtifactReadRootError.reservedRootID(reserved)) {
            try LogicArtifactReadRoot(rootID: reserved, directoryURL: external)
        }
        let remote = try #require(URL(string: "https://example.invalid/pdk"))
        #expect(throws: LogicArtifactReadRootError.fileDirectoryRequired) {
            try LogicArtifactReadRoot(rootID: grant.rootID, directoryURL: remote)
        }
    }
}
