import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicEngineRuntime
import LogicKernelCore
import STAEngine
import Testing
import TimingCore

@Suite(.timeLimit(.minutes(1)))
struct OperatingProcessScopeTests {
    private struct Control: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) {}
    }
    private static let rtl = "module top(input [1:0] d,input c,output logic [1:0] q);wire nc;assign nc=~c;always_ff @(posedge nc) q<=d;endmodule"
    private static let liberty = """
    library (fixture) {
      time_unit:"1ns";capacitive_load_unit(1,pf);
      cell(INV){area:1;pg_pin(VPWR){pg_type:primary_power;}pg_pin(VGND){pg_type:primary_ground;}
        pin(A){direction:input;}pin(Y){direction:output;function:"!A";power_down_function:"!VPWR + VGND";}}
      cell(FF){area:2;pg_pin(VPWR){pg_type:primary_power;}pg_pin(VGND){pg_type:primary_ground;}
        ff(S,SN){next_state:"D";clocked_on:"C";}
        pin(D){direction:input;}pin(C){direction:input;}
        pin(Q){direction:output;function:"S";power_down_function:"!VPWR + VGND";}}
    }
    """
    private func request(root: URL, timing: Bool = false, scopeOverride: LogicOperatingProcessScope? = nil,
                         limits: LogicRuntimeLimits? = nil) throws -> LogicEngineRuntime.LogicSynthesisRequest {
        let base = try ActualCellTimingTests().request(root: root, sourceText: Self.rtl, libraryText: Self.liberty)
        let scope = try #require(base.operatingProcessScope)
        return .init(runID: base.runID, sources: base.sources, roots: base.roots, top: base.top,
            library: base.library, limits: limits ?? base.limits,
            constraints: timing ? base.constraints : .init(), operatingConditionPolicies: ["INV", "FF"].map {
                .init(library: base.library.reference, cell: $0, cornerID: "typical", conditions: [
                    .init(pin: "VPWR", sourcePGType: "primary_power", value: true),
                    .init(pin: "VGND", sourcePGType: "primary_ground", value: false)])
            }, operatingProcessScope: scopeOverride ?? scope)
    }

    @Test func originalInverterDerivedClockProvesAndReloadsWithoutBaselineSTA() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root), store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        #expect(request.constraints.timing == nil && request.operatingProcessScope != nil)
        #expect(result.payload.timingResult == nil && result.payload.proofKind == "state-preserving-induction-rup")
        #expect(result.payload.schemaVersion == 4)
        let verified = try await engine.load(result.receipt, limits: request.limits)
        try verified.equivalence.requireBinding(to: verified.problem)
        var run = LogicKernelContext(limits: try request.limits.kernelLimits(), control: Control())
        let expanded = try verified.qualifyOperatingConditions(verified.mapped, context: &run)
        #expect(expanded.receipt.records.count == verified.mapped.instanceCount && verified.mapped.stateCount == 2)
        #expect(expanded.receipt.records.allSatisfy { $0.cornerID == "typical" && $0.library == request.library.reference
            && $0.normalPower.pgValues.count == 2 && $0.normalPower.functions.allSatisfy { !$0.result } })
        #expect(verified.mapped.withTables { _, instances, _, _, _, _ in instances.indices.allSatisfy { instances[$0].initialValue == nil } })
        #expect(request.inputs.contains(try #require(request.operatingProcessScope).pdkManifest.reference))
    }

    @Test func explicitScopeCannotBypassRequestedSTAOrContradictItsSourceSelection() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root, timing: true)
        #expect(request.operatingProcessScope == request.constraints.timing?.operatingProcessScope)
        await #expect(throws: LogicRuntimeError.self) {
            try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)).execute(request)
        }
        let scope = try #require(request.operatingProcessScope)
        let different = LogicOperatingProcessScope(libraries: scope.libraries, pdkManifest: scope.pdkManifest,
            processID: "different-process", pdkVersion: scope.pdkVersion, cornerIDs: scope.cornerIDs,
            characterizationBindings: scope.characterizationBindings)
        let conflicting = try self.request(root: root, timing: true, scopeOverride: different)
        #expect(throws: LogicKernelError.self) { try conflicting.validate() }
    }

    @Test func nilForeignMissingAndMismatchedSourceFactsCannotEstablishCorners() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let base = try request(root: root), scope = try #require(base.operatingProcessScope)
        let sourceOnly = LogicEngineRuntime.LogicSynthesisRequest(runID: base.runID, sources: base.sources,
            roots: base.roots, top: base.top, library: base.library, limits: base.limits,
            operatingConditionPolicies: base.operatingConditionPolicies)
        #expect(sourceOnly.operatingProcessScope == nil)
        #expect(throws: LogicKernelError.self) { try sourceOnly.validate() }
        let wrongReference = ArtifactReference(id: base.library.id, descriptor: .init(role: .output, kind: .rtl, format: .liberty))
        let foreign = try TimingArtifactBinding(reference: wrongReference, availability: base.library.availability)
        let invalid: [LogicOperatingProcessScope] = [
            .init(libraries: [.init(artifact: foreign, cornerIDs: scope.cornerIDs)], pdkManifest: scope.pdkManifest,
                processID: scope.processID, pdkVersion: scope.pdkVersion, cornerIDs: scope.cornerIDs, characterizationBindings: scope.characterizationBindings),
            .init(libraries: scope.libraries, pdkManifest: scope.pdkManifest, processID: "foreign", pdkVersion: scope.pdkVersion,
                cornerIDs: scope.cornerIDs, characterizationBindings: scope.characterizationBindings),
            .init(libraries: scope.libraries, pdkManifest: scope.pdkManifest, processID: scope.processID, pdkVersion: "foreign",
                cornerIDs: scope.cornerIDs, characterizationBindings: scope.characterizationBindings),
            .init(libraries: [.init(artifact: scope.libraries[0].artifact, cornerIDs: ["missing"])], pdkManifest: scope.pdkManifest,
                processID: scope.processID, pdkVersion: scope.pdkVersion, cornerIDs: ["missing"], characterizationBindings: [.init(cornerID: "missing", conditionName: "typical")]),
            .init(libraries: scope.libraries, pdkManifest: scope.pdkManifest, processID: scope.processID, pdkVersion: scope.pdkVersion,
                cornerIDs: scope.cornerIDs, characterizationBindings: [.init(cornerID: "typical", conditionName: "absent")]),
            .init(libraries: scope.libraries, pdkManifest: scope.pdkManifest, processID: scope.processID, pdkVersion: scope.pdkVersion,
                cornerIDs: scope.cornerIDs, characterizationBindings: [.init(cornerID: "typical", conditionName: "typical", requiredNumericProcess: 2)])]
        for invalidScope in invalid {
            let bad = LogicEngineRuntime.LogicSynthesisRequest(runID: base.runID, sources: base.sources,
                roots: base.roots, top: base.top, library: base.library, limits: base.limits,
                operatingConditionPolicies: base.operatingConditionPolicies, operatingProcessScope: invalidScope)
            await #expect(throws: (any Error).self) {
                try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)).execute(bad)
            }
        }
        let bounded = try request(root: root, limits: helper.limits(tables: 4))
        await #expect(throws: (any Error).self) {
            try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)).execute(bounded)
        }
    }

    @Test func oldSchemaOrReboundScopeCannotAuthorizeCheckedReload() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root), store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store), result = try await engine.execute(request)
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        old["schemaVersion"] = ["major": 6, "minor": 0, "patch": 0]
        let oldRequest = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisRequest.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(throws: LogicKernelError.self) { try oldRequest.validate() }
        for mutateRequest in [false, true] {
            var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
            if !mutateRequest { receipt["schemaVersion"] = 3 }
            else {
                var document = try #require(JSONSerialization.jsonObject(with: store.read(result.payload.request)) as? [String: Any])
                var scope = try #require(document["operatingProcessScope"] as? [String: Any])
                scope["processID"] = "forged-process"; document["operatingProcessScope"] = scope
                let rebound = try store.write(JSONSerialization.data(withJSONObject: document), fileName: "forged-scope-request.json",
                    outputDirectory: nil, runID: "scope-forgery", kind: .request, format: .json)
                receipt["request"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rebound))
            }
            let rebound = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "forged-scope-receipt-\(mutateRequest).json",
                outputDirectory: nil, runID: "scope-forgery", kind: .report, format: .json)
            await #expect(throws: (any Error).self) { try await engine.load(rebound, limits: request.limits) }
        }
    }
}
