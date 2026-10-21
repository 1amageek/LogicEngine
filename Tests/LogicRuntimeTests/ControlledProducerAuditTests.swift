import CircuiteFoundation
import CircuiteFoundationFileSystem
import Foundation
import LogicEngineCore
@testable import LogicEngineRuntime
import LogicKernelCore
import PDKCore
import PDKDiscovery
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(2)))
struct ControlledProducerAuditTests {
    private final class AuditControl: LogicReloadResourceControlling {
        final class Refusal: Error, Sendable {}
        enum Action: Sendable { case none, cancelA, cancelB }
        struct State: Sendable {
            var allowance: UInt64?
            var action = Action.none
            var armed = false
            var cancelled = false
            var callbacksAfterCancellation = 0
            var auditCompleted = false
        }
        let original = ControlledReloadTestControl()
        let base = ControlledReloadTestLedger()
        let refusal = Refusal()
        private let state = Mutex(State())
        var snapshot: ControlledReloadTestLedger.State { base.snapshot }
        var callbacksAfterCancellation: Int { state.withLock { $0.callbacksAfterCancellation } }
        var auditCompleted: Bool { state.withLock { $0.auditCompleted } }
        func arm(allowance: UInt64?, action: Action) {
            state.withLock { $0.allowance = allowance; $0.action = action; $0.armed = true }
        }
        func completed() { state.withLock { $0.auditCompleted = true } }
        func check() throws {
            if state.withLock({ $0.cancelled }) { throw refusal }
            try base.check()
        }
        private func entry() throws {
            let originalCancelled = original.isCancelled
            let cancelled = state.withLock { value in
                if originalCancelled || value.cancelled {
                    value.callbacksAfterCancellation += 1
                    return true
                }
                return false
            }
            if cancelled { throw refusal }
        }
        func charge(_ resource: LogicResource, amount: UInt64) throws {
            try entry()
            let action = try state.withLock { value throws -> Action in
                guard resource == .workUnits, value.armed else { return .none }
                if let allowance = value.allowance {
                    guard amount <= allowance else { throw refusal }
                    value.allowance = allowance - amount
                }
                let action = value.action
                value.action = .none
                return action
            }
            try base.charge(resource, amount: amount)
            // The callback completes outside the state lock before cancellation is observed.
            switch action {
            case .none: break
            case .cancelA: original.cancel()
            case .cancelB: state.withLock { $0.cancelled = true }
            }
        }
        func observeBitWidth(_ width: UInt64) throws { try entry(); try base.observeBitWidth(width) }
        func reserveStorage(byteCount: UInt64) throws -> any LogicKernelStorageRetaining {
            try entry(); return try base.reserveStorage(byteCount: byteCount)
        }
        func chargeArtifact(_ work: ArtifactSourceWork) throws { try entry(); try base.chargeArtifact(work) }
        func retainArtifact(_ extent: ArtifactSourceExtent) throws -> any ArtifactSourceRetention {
            try entry(); return try base.retainArtifact(extent)
        }
    }

    private struct Fixture {
        let root: URL
        let request: LogicSynthesisRequest
        let engine: NativeLogicSynthesisEngine
        let store: FileSystemLogicArtifactStore
        let result: LogicSynthesisResult
        let data: Data
    }
    private struct Measurement {
        let document: PDKDecodedDocument<LogicSynthesisReceipt>
        let customWork: UInt64
    }
    private func fixture() async throws -> Fixture {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        do {
            let request = try helper.request(root: root)
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let engine = NativeLogicSynthesisEngine(artifactStore: store)
            let result = try await engine.execute(request)
            return .init(root: root, request: request, engine: engine, store: store,
                result: result, data: try store.read(result.receipt))
        } catch {
            do { try FileManager.default.removeItem(at: root) }
            catch let cleanup { Issue.record(cleanup) }
            throw error
        }
    }
    private func rewritten(_ fixture: Fixture, field: String, text: String) throws
        -> (binding: LogicArtifactBinding, data: Data) {
        var object = try #require(JSONSerialization.jsonObject(with: fixture.data) as? [String: Any])
        var producer = try #require(object["producer"] as? [String: Any])
        producer[field] = text; object["producer"] = producer
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let binding = try fixture.store.write(data, fileName: "producer-\(field).json",
            outputDirectory: nil, runID: "producer-audit", kind: .report, format: .json)
        #expect(binding.id != fixture.result.receipt.id)
        return (binding, try fixture.store.read(binding))
    }
    private func measure(_ data: Data, limits: LogicRuntimeLimits, control: AuditControl,
        allowance: UInt64? = nil, action: AuditControl.Action = .none) throws -> Measurement {
        let resources = LogicReloadResources(control: control)
        var context = LogicKernelContext(limits: try limits.kernelLimits(), control: control.original,
            accounting: resources)
        try context.charge(.workUnits, amount: 17)
        var customWork: UInt64 = 0
        let decoded = try LogicReloadDocumentDecoding.decode(LogicSynthesisReceipt.self, data: data,
            limits: limits, context: &context, resources: resources) { decoder in
                // Parsing and generic decoder setup have already completed at this boundary.
                let before = control.snapshot.work
                control.arm(allowance: allowance, action: action)
                try LogicReloadCodingAudit.receipt(decoder)
                customWork = control.snapshot.work - before
                control.completed()
            }
        #expect(context.usage[.workUnits] == control.snapshot.work)
        return .init(document: decoded, customWork: customWork)
    }
    private func originalToken(_ value: LogicSynthesisReceipt, field: String) throws -> String {
        switch field {
        case "identifier": return value.producer.identifier
        case "version": return value.producer.version
        default: return try #require(value.producer.build)
        }
    }

    @Test(arguments: ["identifier", "version", "build", "build-unicode"])
    func realReceiptProducerCustomWorkIncludesOriginalTokenScans(_ sample: String) async throws {
        let f = try await fixture()
        defer { do { try FileManager.default.removeItem(at: f.root) } catch { Issue.record(error) } }
        let field = sample == "build-unicode" ? "build" : sample
        let text = sample == "build-unicode" ? String(repeating: "e\u{301}", count: 2050)
            : String(repeating: "a", count: 4099)
        let changed = try rewritten(f, field: field, text: text)
        let shortControl = AuditControl(), longControl = AuditControl()
        let shortWork: UInt64
        do {
            let short = try measure(f.data, limits: f.request.limits, control: shortControl)
            shortWork = short.customWork
        }
        #expect(shortControl.snapshot.live == 0)
        var retained: PDKDecodedDocument<LogicSynthesisReceipt>?
        do {
            let long = try measure(changed.data, limits: f.request.limits, control: longControl)
            let original = try originalToken(f.result.payload, field: field)
            let extra = UInt64(text.utf8.count - original.utf8.count) * 3
            #expect(long.customWork >= shortWork + extra)
            let decodedToken = try originalToken(long.document.value, field: field)
            #expect(decodedToken.utf8.elementsEqual(text.utf8))
            retained = long.document
        }
        var lastCopy = retained; retained = nil
        #expect(longControl.snapshot.live > 0)
        withExtendedLifetime(lastCopy) {}
        lastCopy = nil
        #expect(longControl.snapshot.live == 0 && longControl.snapshot.open == 0)
        if field == "build" {
            let ledger = ControlledReloadTestLedger(), resources = LogicReloadResources(control: ledger)
            var context = LogicKernelContext(limits: try f.request.limits.kernelLimits(),
                control: AuditControl().original, accounting: resources)
            do {
                let loaded = try await f.engine.load(changed.binding, limits: f.request.limits,
                    context: &context, resources: resources)
                try loaded.value.equivalence.requireBinding(to: loaded.value.problem)
                #expect(loaded.value.receipt.producer.build?.utf8.elementsEqual(text.utf8) == true)
                withExtendedLifetime(loaded.retention) {}
            }
            #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
        }
    }

    @Test(arguments: ["quota", "cancel-a", "cancel-b"])
    func actualProducerAuditRefusalPrecedesOriginalCustomConstruction(_ mode: String) async throws {
        let f = try await fixture()
        defer { do { try FileManager.default.removeItem(at: f.root) } catch { Issue.record(error) } }
        let changed = try rewritten(f, field: "build", text: String(repeating: "b", count: 4099))
        let baseline = AuditControl(), required: UInt64
        do { required = try measure(changed.data, limits: f.request.limits, control: baseline).customWork }
        #expect(required > 0 && baseline.snapshot.live == 0)
        let control = AuditControl()
        let action: AuditControl.Action = mode == "cancel-a" ? .cancelA : mode == "cancel-b" ? .cancelB : .none
        do {
            _ = try measure(changed.data, limits: f.request.limits, control: control,
                allowance: mode == "quota" ? required - 1 : nil, action: action)
            Issue.record("Refused producer audit published a decoded receipt")
        } catch {
            guard let failure = error as? LogicControlledReloadFailure,
                  let lower = failure.secondary as? PDKControlledDecodeFailure,
                  case .resource(.unsupportedBudgetCapability(
                    "Caller accounting failed; original cause retained by invocation.")) = lower.cause else {
                Issue.record("Original controlled decode failure chain changed: \(error)"); return
            }
            if mode == "cancel-a" {
                guard let cause = failure.primary as? LogicKernelError, case .cancelled = cause else {
                    Issue.record("Original caller cancellation cause changed: \(failure.primary)"); return
                }
            } else { #expect((failure.primary as? AuditControl.Refusal) === control.refusal) }
        }
        #expect(!control.auditCompleted)
        #expect(control.callbacksAfterCancellation == 0)
        #expect(control.snapshot.live == 0 && control.snapshot.open == 0)
    }

    @Test func originalProducerTokenFailureKeepsItsLastCopiedLowerOwner() async throws {
        let f = try await fixture()
        defer { do { try FileManager.default.removeItem(at: f.root) } catch { Issue.record(error) } }
        let changed = try rewritten(f, field: "build", text: String(repeating: "c", count: 4099) + "\u{0}")
        let control = AuditControl()
        var retained: PDKControlledDecodeFailure?
        do {
            do {
                _ = try measure(changed.data, limits: f.request.limits, control: control)
                Issue.record("Original CF token validation accepted a control character")
            } catch let failure as PDKControlledDecodeFailure {
                guard case .unsupportedValue("Document violates its checked Codable contract") = failure.cause else {
                    Issue.record("Original controlled decoder token failure changed: \(failure.cause)"); return
                }
                retained = failure
            }
        }
        #expect(control.auditCompleted)
        var lastCopy = retained; retained = nil
        #expect(control.snapshot.live > 0)
        withExtendedLifetime(lastCopy) {}
        lastCopy = nil
        #expect(control.snapshot.live == 0 && control.snapshot.open == 0)
    }
}
