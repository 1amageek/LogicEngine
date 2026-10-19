import CircuiteFoundation
import Foundation
import LogicDesignSerialization
import LogicEngineCore
import LogicEngineRuntime
import LogicIR
import LogicKernelCore
import STAEngine
import Testing
import TimingCore

@Suite(.timeLimit(.minutes(1)))
struct ActualCellOperatingConditionTests {
    private static let source = """
    library(L){
      cell(INV){area:1;pg_pin(VPWR){pg_type:primary_power;}pg_pin(VGND){pg_type:primary_ground;}
        pin(A){direction:input;}pin(Y){direction:output;function:"!A";power_down_function:"!VPWR + VGND";}}
      cell(UNUSED){area:20;pg_pin(VPWR){pg_type:primary_power;}pg_pin(VGND){pg_type:primary_ground;}
        pin(A){direction:input;}pin(Y){direction:output;function:"!A";power_down_function:"!VPWR + VGND";}}
      cell(BUF){area:1;pin(A){direction:input;}pin(Y){direction:output;function:"A";}}
    }
    """
    private static let values: [LibertyPGCondition] = [
        .init(pin: "VPWR", sourcePGType: "primary_power", value: true),
        .init(pin: "VGND", sourcePGType: "primary_ground", value: false)]

    private struct Control: LogicRunControlling {
        var cancelled = false
        func checkpoint() throws(LogicKernelError) { if cancelled { throw .cancelled } }
    }
    private func context(limit: UInt64 = 1_000_000_000, cancelled: Bool = false) throws -> LogicKernelContext {
        .init(limits: try .init(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, limit) })),
              control: Control(cancelled: cancelled))
    }
    private func conditioned(_ request: LogicEngineRuntime.LogicSynthesisRequest,
                             policies: [LogicOperatingConditionPolicy]) -> LogicEngineRuntime.LogicSynthesisRequest {
        .init(runID: request.runID, sources: request.sources, roots: request.roots, top: request.top,
              library: request.library, limits: request.limits, constraints: request.constraints,
              realizationPolicy: request.realizationPolicy, operatingConditionPolicies: policies)
    }
    private func request(root: URL) throws -> LogicEngineRuntime.LogicSynthesisRequest {
        let helper = ActualCellRuntimeTests()
        let base = try helper.request(root: root, source: "module top(input [1:0] a,output [1:0] y);assign y=~a;endmodule")
        let library = try helper.input(Data(Self.source.utf8), name: "conditions.lib", format: .liberty, root: root)
        return .init(runID: base.runID, sources: base.sources, roots: base.roots, top: base.top,
            library: library, limits: base.limits, operatingConditionPolicies: ["INV", "UNUSED"].map {
                .init(library: library.reference, cell: $0, conditions: Self.values)
            })
    }

    @Test func explicitPoliciesExpandAndReloadWithoutNarrowingBinaryProof() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root), store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        let verified = try await engine.load(result.receipt, limits: request.limits)
        try verified.equivalence.requireBinding(to: verified.problem)
        let conditions = verified.operatingConditions.receipt
        #expect(conditions.policies == request.operatingConditionPolicies)
        #expect(conditions.records.count == 2 && conditions.unusedPolicyIndices == [1])
        #expect(conditions.policyOutcomes.count == 2)
        for record in conditions.records {
            #expect(record.cellName == "INV" && record.cornerID == nil && record.policyIndex == 0)
            #expect(record.library == request.library.reference)
            #expect(record.normalPower.pgValues.map(\.condition) == Self.values)
            #expect(record.normalPower.functions.count == 1 && record.normalPower.functions.allSatisfy { !$0.result })
        }
        let simulation = LogicEngineRuntime.LogicSimulationRequest(runID: "conditioned-events", mappedReceipt: result.receipt,
            events: [.init(time: 1, updates: [.init(portIndex: 0, value: "00")]),
                     .init(time: 2, updates: [.init(portIndex: 0, value: "11")])], limits: request.limits)
        let observed = try await LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store).execute(simulation)
        #expect(observed.observations.last?.outputs.first?.value == "00")
        #expect(observed.observations.contains { $0.outputs.first?.value == "11" })
    }

    @Test func missingDuplicateForeignAndInvalidUnusedPoliciesCannotComplete() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let base = try request(root: root), normal = base.operatingConditionPolicies
        let off = LogicOperatingConditionPolicy(library: base.library.reference, cell: "UNUSED", conditions: [
            .init(pin: "VPWR", sourcePGType: "primary_power", value: false), Self.values[1]])
        let typo = LogicOperatingConditionPolicy(library: base.library.reference, cell: "TYPO", conditions: Self.values)
        let uncertain = Self.source.replacingOccurrences(of: "!VPWR + VGND", with: "!VPWR + A")
        for policies in [[], [normal[0], normal[0]], [normal[0], off], [normal[0], typo]] {
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
            await #expect(throws: (any Error).self) { try await engine.execute(conditioned(base, policies: policies)) }
        }
        let library = try helper.input(Data(uncertain.utf8), name: "uncertain.lib", format: .liberty, root: root)
        let unknown = LogicEngineRuntime.LogicSynthesisRequest(runID: base.runID, sources: base.sources, roots: base.roots,
            top: base.top, library: library, limits: base.limits, operatingConditionPolicies: [
                .init(library: library.reference, cell: "INV", conditions: Self.values)])
        await #expect(throws: (any Error).self) {
            try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)).execute(unknown)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/actual-runtime/synthesis-receipt-v4.json").path))
    }

    private func candidate(library: LogicTechnologyLibrary, context: inout LogicKernelContext) throws -> MappedGateDesign {
        var builder = try MappedGateBuilder(library: library,
            capacity: .init(nets: 4, instances: 3, pinConnections: 6, ports: 2, portBits: 2), context: &context)
        _ = try builder.addNet(.init(id: .init(rawValue: 9_000_000), driver: .input), context: &context)
        for index in 0..<3 {
            _ = try builder.addNet(.init(id: .init(rawValue: UInt64(9_000_001 + index)),
                driver: .instanceOutput(.init(index), .init(1))), context: &context)
        }
        for index in 0..<3 {
            _ = try builder.addInstance(id: .init(rawValue: UInt64(9_000_100 + index)),
                cell: .init(index == 2 ? 2 : 0), pinNets: [.init(index), .init(index + 1)], context: &context)
        }
        try builder.addPort(id: .init(rawValue: 9_000_200), direction: .input, nets: [.init(0)], context: &context)
        try builder.addPort(id: .init(rawValue: 9_000_201), direction: .output, nets: [.init(3)], context: &context)
        return try builder.finish(context: &context)
    }

    @Test func candidateQualificationCoversNewInstancesAndUnconditionalCellsUnderFreshBudget() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root), engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let result = try await engine.execute(request), baseline = try await engine.load(result.receipt, limits: request.limits)
        var run = try context()
        let graph = try candidate(library: baseline.mapped.library, context: &run)
        let checked = try baseline.qualifyOperatingConditions(graph, context: &run)
        #expect(checked.receipt.records.map(\.instanceID.rawValue) == [9_000_100, 9_000_101, 9_000_102])
        #expect(checked.receipt.records.map(\.cellName) == ["INV", "INV", "BUF"])
        #expect(checked.receipt.records.last?.policyIndex == nil)
        #expect(checked.receipt.records.last?.normalPower.pgValues.isEmpty == true)
        #expect(checked.receipt.records.last?.normalPower.functions.isEmpty == true)
        for (limit, cancelled) in [(UInt64(1), false), (UInt64(1_000_000_000), true)] {
            var limited = try context(limit: limit, cancelled: cancelled)
            #expect(throws: LogicOperatingConditionError.self) { try baseline.qualifyOperatingConditions(graph, context: &limited) }
        }
        var libraryBuilder = try LogicTechnologyLibraryBuilder(cellCapacity: baseline.mapped.library.cellCount,
            totalPinCapacity: baseline.mapped.library.cellCount * 2, context: &run)
        for index in 0..<baseline.mapped.library.cellCount {
            let old = try baseline.mapped.library.cell(at: .init(index))
            var cell = try LogicTechnologyCellBuilder(id: old.id, name: old.name, pinCapacity: old.pinCount, context: &run)
            for p in 0..<old.pinCount {
                let pin = try old.pin(at: .init(p))
                var function = pin.function
                if index == 0 && p == 1 {
                    var replacement = try LogicBooleanFunctionBuilder(inputCount: 2, nodeCapacity: 1, context: &run)
                    let output = try replacement.append(.input(0), context: &run)
                    function = try replacement.finish(output: output, context: &run)
                }
                _ = try cell.append(.init(id: pin.id, name: pin.name, direction: pin.direction, function: function), context: &run)
            }
            _ = try libraryBuilder.append(cell.finish(area: old.area, state: old.state, context: &run), context: &run)
        }
        let changed = try libraryBuilder.finish(source: baseline.mapped.library.source, context: &run)
        let forged = try candidate(library: changed, context: &run)
        #expect(throws: LogicOperatingConditionError.self) { try baseline.qualifyOperatingConditions(forged, context: &run) }
    }

    @Test func transportOutcomesAndOldReceiptsCannotAuthorizeReload() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root), store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store), result = try await engine.execute(request)
        for mutation in 0..<4 {
            var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
            if mutation == 0 { receipt["schemaVersion"] = 2 }
            if mutation == 1 { receipt["algorithm"] = "logic.actual-cell.synthesis.v5" }
            if mutation >= 2 {
                var conditions = try #require(receipt["operatingConditions"] as? [String: Any])
                if mutation == 2 { conditions["records"] = [] }
                else { conditions["unusedPolicyIndices"] = [] }
                receipt["operatingConditions"] = conditions
            }
            let rebound = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "forged-conditions-\(mutation).json",
                outputDirectory: nil, runID: "forged-conditions", kind: .report, format: .json)
            await #expect(throws: (any Error).self) { try await engine.load(rebound, limits: request.limits) }
        }
    }

    @Test func candidateExpansionSurvivesTheOriginalSourceRunDeadline() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let base = try request(root: root)
        let limits = helper.limits(timeout: 2_000_000_000)
        let request = LogicEngineRuntime.LogicSynthesisRequest(runID: base.runID, sources: base.sources,
            roots: base.roots, top: base.top, library: base.library, limits: limits,
            operatingConditionPolicies: base.operatingConditionPolicies)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let result = try await engine.execute(request)
        let baseline = try await engine.load(result.receipt, limits: limits)
        // The loaded source accountant's original two-second deadline expires before the new run starts.
        try await Task.sleep(for: .milliseconds(2_100))
        var run = try context()
        let graph = try candidate(library: baseline.mapped.library, context: &run)
        let expanded = try baseline.qualifyOperatingConditions(graph, context: &run)
        #expect(expanded.receipt.records.count == 3)
        #expect(expanded.receipt.records.prefix(2).allSatisfy { $0.normalPower.pgValues.map(\.condition) == Self.values })
    }

    @Test func exactCornerConditionsAreForwardedToNativeSTAAndReplay() async throws {
        let helper = ActualCellRuntimeTests(), root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let fixtures = try #require(Bundle.module.resourceURL).appending(path: "Fixtures/timing.lib")
        let original = String(decoding: try Data(contentsOf: fixtures), as: UTF8.self)
        let text = original.replacingOccurrences(of: "cell (INV) {", with: "cell (INV) { pg_pin(VPWR){pg_type:primary_power;} pg_pin(VGND){pg_type:primary_ground;}")
            .replacingOccurrences(of: "function : \"!A\";", with: "function : \"!A\"; power_down_function:\"!VPWR + VGND\";")
        let base = try ActualCellTimingTests().request(root: root, libraryText: text)
        let policy = LogicOperatingConditionPolicy(library: base.library.reference, cell: "INV", cornerID: "typical", conditions: Self.values)
        let request = conditioned(base, policies: [policy]), store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store), result = try await engine.execute(request)
        let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
        let assumptions = try #require(sta.payload.effectiveConfiguration).operatingSupplyAssumptions
        #expect(assumptions.count == 2 && assumptions.allSatisfy { $0.instance == "i0" && $0.cell == "INV" && $0.cornerID == "typical" && $0.library == base.library.reference })
        #expect(assumptions.contains { $0.pin == "VPWR" && $0.value == .one })
        #expect(assumptions.contains { $0.pin == "VGND" && $0.value == .zero })
        _ = try await engine.load(result.receipt, limits: request.limits)
        for corner in [String?.none, "wrong-corner"] {
            let wrong = LogicOperatingConditionPolicy(library: base.library.reference, cell: "INV", cornerID: corner, conditions: Self.values)
            #expect(throws: LogicKernelError.self) { try conditioned(base, policies: [wrong]).validate() }
        }
        let foreign = ArtifactReference(id: base.library.id, descriptor: .init(role: .output, kind: .rtl, format: .liberty))
        #expect(throws: LogicKernelError.self) {
            try conditioned(base, policies: [.init(library: foreign, cell: "INV", cornerID: "typical", conditions: Self.values)]).validate()
        }
    }
}
