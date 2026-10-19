import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicEngineRuntime
import LogicIR
import STAEngine
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ActualCellRealizationTests {
    private func temporary() throws -> URL {
        guard let directory = ProcessInfo.processInfo.environment["LOGIC_ENGINE_EVIDENCE_ROOT"] else {
            return try ActualCellRuntimeTests().temporary()
        }
        let root = URL(fileURLWithPath: directory).appending(path: "realization-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func cleanup(_ root: URL) throws {
        if ProcessInfo.processInfo.environment["LOGIC_ENGINE_EVIDENCE_ROOT"] == nil {
            try FileManager.default.removeItem(at: root)
        }
    }
    func request(root: URL, policy: LogicSynthesisRealizationPolicy, withTies: Bool = true) throws -> LogicSynthesisRequest {
        let helper = ActualCellRuntimeTests()
        let base = try helper.request(root: root, source: "module top(output [3:0] y);assign y=4'b1010;endmodule")
        let text = withTies ? ActualCellRuntimeTests.liberty.replacingOccurrences(of: "library(L){",
            with: "library(L){cell(DUAL_TIE){area:2;pin(LO){direction:output;function:\"0\";}pin(HI){direction:output;function:\"!0\";}}")
            : ActualCellRuntimeTests.liberty
        let library = try helper.input(Data(text.utf8), name: "cells.lib", format: .liberty, root: root)
        return .init(runID: base.runID, sources: base.sources, roots: base.roots, top: base.top, library: library,
                     limits: base.limits, realizationPolicy: policy)
    }
    @Test func physicalTieCellsExecuteActualFunctionsAndCheckedReceiptReplay() async throws {
        let helper = ActualCellRuntimeTests(); let root = try temporary()
        defer { do { try cleanup(root) } catch { Issue.record(error) } }
        let request = try request(root: root, policy: .physicalCells)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        #expect(result.payload.schemaVersion == 4 && result.payload.realizationPolicy == .physicalCells)
        #expect(result.payload.instanceCount == 1 && result.payload.area == 2)
        let loaded = try await engine.load(result.receipt, limits: request.limits)
        try loaded.equivalence.requireBinding(to: loaded.problem)
        #expect(loaded.mapped.withTables { nets, _, _, _, _, _ in
            nets.indices.allSatisfy { if case .instanceOutput = nets[$0].driver { return true }; return false }
        })
        let bytes = String(decoding: try store.read(result.payload.netlist), as: UTF8.self)
        #expect(bytes.contains("\\DUAL_TIE ") && !bytes.contains("1'b"))
        let observed = try await NativeLogicSimulationEngine(artifactStore: store).execute(
            .init(runID: "physical-tie-events", mappedReceipt: result.receipt, events: [], limits: request.limits))
        #expect(observed.observations[0].outputs[0].value == "1010")
    }
    @Test func missingTieCapabilityRefusesWhileStandardConstantsRemainSupported() async throws {
        for policy in [LogicSynthesisRealizationPolicy.standardNetlist, .physicalCells] {
            let helper = ActualCellRuntimeTests(); let root = try temporary()
            defer { do { try cleanup(root) } catch { Issue.record(error) } }
            let request = try request(root: root, policy: policy, withTies: false)
            let engine = NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
            if policy == .physicalCells {
                await #expect(throws: LogicRuntimeError.self) { try await engine.execute(request) }
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/actual-runtime/synthesis-receipt-v4.json").path))
            } else {
                let result = try await engine.execute(request)
                #expect(result.payload.instanceCount == 0)
                _ = try await engine.load(result.receipt, limits: request.limits)
            }
        }
    }
    @Test func rehashedPolicyCannotUpgradeLogicalConstantsOrOldReceiptAuthority() async throws {
        let helper = ActualCellRuntimeTests(); let root = try temporary()
        defer { do { try cleanup(root) } catch { Issue.record(error) } }
        let request = try request(root: root, policy: .standardNetlist)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        var requestObject = try #require(JSONSerialization.jsonObject(with: store.read(result.payload.request)) as? [String: Any])
        requestObject["realizationPolicy"] = "physicalCells"
        let changedRequest = try store.write(JSONSerialization.data(withJSONObject: requestObject), fileName: "request.json",
            outputDirectory: nil, runID: "forged", kind: .request, format: .json)
        var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
        receipt["request"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changedRequest))
        receipt["realizationPolicy"] = "physicalCells"
        let changedReceipt = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "receipt.json",
            outputDirectory: nil, runID: "forged", kind: .report, format: .json)
        await #expect(throws: (any Error).self) { try await engine.load(changedReceipt, limits: request.limits) }
        receipt["algorithm"] = "logic.actual-cell.synthesis.v4"
        let old = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "old.json",
            outputDirectory: nil, runID: "forged", kind: .report, format: .json)
        await #expect(throws: (any Error).self) { try await engine.load(old, limits: request.limits) }
    }
    @Test func requiredSTASeesExactPhysicalTieInstancesAndAllStaticAliases() async throws {
        let root = try temporary()
        defer { do { try cleanup(root) } catch { Issue.record(error) } }
        let base = try ActualCellTimingTests().request(root: root,
            sourceText: "module top(input clk,output [3:0] y);assign y=4'b1010;endmodule",
            sdcText: "create_clock -name clk -period 10ns [get_ports p0_0]\n"
                + (0..<4).map { "set_output_delay 2ns -clock clk [get_ports p1_\($0)]" }.joined(separator: "\n"),
            libraryText: "library (fixture) {cell(DUAL_TIE){area:2;pin(LO){direction:output;function:\"0\";}pin(HI){direction:output;function:\"!0\";}}}",
            requiredHoldSlack: 0)
        let request = LogicSynthesisRequest(runID: base.runID, sources: base.sources, roots: base.roots,
            top: base.top, library: base.library, limits: base.limits, constraints: base.constraints, realizationPolicy: .physicalCells)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        let reloaded = try await engine.load(result.receipt, limits: request.limits)
        try reloaded.equivalence.requireBinding(to: reloaded.problem)
        #expect(result.payload.instanceCount == 1 && result.payload.area == 2)
        let timing = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
        #expect(timing.payload.worstSetupSlack == nil && timing.payload.worstHoldSlack == nil)
        #expect(timing.payload.endpoints.count == 4)
        for index in 0..<4 {
            let endpoint = try #require(timing.payload.endpoints.first { $0.endpoint == "p1_\(index)" })
            #expect(endpoint.staticValue == (index % 2 == 0 ? .zero : .one))
            #expect(endpoint.staticChecks == [.setup, .hold] && endpoint.unconstrainedChecks?.isEmpty != false)
        }
        try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
        // A distinct run keeps immutable API and actual CLI artifacts independently reproducible.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        object["runID"] = "cli-tie-sta"
        try JSONSerialization.data(withJSONObject: object).write(to: root.appending(path: "cli-request.json"))
        let cli = ActualCellCLITests()
        let executed = try cli.run(["synthesize", "--request", "cli-request.json", "--root", root.path], root: root)
        try executed.1.write(to: root.appending(path: "cli-tie-sta-output.json"))
        #expect(executed.0 == 0, "\(String(decoding: executed.1, as: UTF8.self))")
        let actual = try JSONDecoder().decode(LogicSynthesisResult.self, from: executed.1)
        let replay = LogicEquivalenceRequest(runID: "cli-tie-sta-replay", receipt: actual.receipt, limits: request.limits)
        try JSONEncoder().encode(replay).write(to: root.appending(path: "cli-tie-sta-replay.json"))
        let checked = try cli.run(["verify-mapped", "--request", "cli-tie-sta-replay.json", "--root", root.path], root: root)
        try checked.1.write(to: root.appending(path: "cli-tie-sta-replay-output.json"))
        #expect(checked.0 == 0)
    }
    @Test func actualCLIRealizesBothTieOutputsAndRefusesMissingCapability() throws {
        let helper = ActualCellRuntimeTests()
        for withTies in [true, false] {
            let root = try temporary()
            defer { do { try cleanup(root) } catch { Issue.record(error) } }
            let request = try request(root: root, policy: .physicalCells, withTies: withTies)
            try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
            let cli = ActualCellCLITests()
            let execution = try cli.run(["synthesize", "--request", "request.json", "--root", root.path], root: root)
            try execution.1.write(to: root.appending(path: "cli-synthesis-output.json"))
            if !withTies {
                #expect(execution.0 != 0)
                #expect(String(decoding: execution.1, as: UTF8.self).contains("tie cell"))
                continue
            }
            #expect(execution.0 == 0, "\(String(decoding: execution.1, as: UTF8.self))")
            let result = try JSONDecoder().decode(LogicSynthesisResult.self, from: execution.1)
            #expect(result.payload.instanceCount == 1)
            let reload = LogicEquivalenceRequest(runID: "cli-physical-replay", receipt: result.receipt, limits: request.limits)
            try JSONEncoder().encode(reload).write(to: root.appending(path: "reload.json"))
            let replayed = try cli.run(["verify-mapped", "--request", "reload.json", "--root", root.path], root: root)
            try replayed.1.write(to: root.appending(path: "cli-reload-output.json"))
            #expect(replayed.0 == 0)
            let simulation = LogicSimulationRequest(runID: "cli-physical-observation", mappedReceipt: result.receipt,
                events: [], limits: request.limits)
            try JSONEncoder().encode(simulation).write(to: root.appending(path: "events.json"))
            let observed = try cli.run(["simulate", "--request", "events.json", "--root", root.path], root: root)
            try observed.1.write(to: root.appending(path: "cli-observation-output.json"))
            #expect(observed.0 == 0)
            #expect(try JSONDecoder().decode(LogicSimulationResult.self, from: observed.1).observations[0].outputs[0].value == "1010")
        }
    }
}
