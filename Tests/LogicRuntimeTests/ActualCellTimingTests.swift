import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicEngineRuntime
import LogicKernelCore
import PDKCore
import STAEngine
import Testing
import TimingCore

@Suite(.timeLimit(.minutes(1)))
struct ActualCellTimingTests {
    @Test func requestedNativeSTAAndObservedConditionSurviveCheckedReload() async throws {
        let helper = ActualCellRuntimeTests()
        for (expression, requiredSlack, succeeds) in [("~a", 0.0, true), ("~a", 1.0, false),
                                                    ("1'b0", 0.0, true), ("a", 0.0, true)] {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, expression: expression, requiredSlack: requiredSlack)
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
            if !succeeds {
                await #expect(throws: LogicRuntimeError.self) { try await engine.execute(request) }
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/native-sta/synthesis-receipt-v4.json").path))
            } else {
                let result = try await engine.execute(request)
                let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
                #expect(sta.status == .completed && sta.payload.characterization.contains { $0.conditionName == "typical" && $0.selected })
                if expression == "1'b0" {
                    #expect(sta.payload.worstSetupSlack == nil && sta.payload.endpoints.allSatisfy { $0.staticValue == .zero })
                } else {
                    #expect(abs(try #require(sta.payload.worstSetupSlack) - (expression == "a" ? 7e-9 : 6e-9)) < 1e-20)
                }
                let reloaded = try await engine.load(result.receipt, limits: request.limits)
                try reloaded.equivalence.requireBinding(to: reloaded.problem)
            }
        }
    }
    func request(root: URL, expression: String = "~a", requiredSlack: Double = 0,
                 runID: String = "native-sta", sourceText: String? = nil, sdcText: String? = nil, libraryFile: String = "timing.lib", libraryText: String? = nil, requiredHoldSlack: Double? = nil) throws -> LogicEngineRuntime.LogicSynthesisRequest {
        let helper = ActualCellRuntimeTests()
        let fixtures = try #require(Bundle.module.resourceURL).appending(path: "Fixtures")
        let text = (try libraryText ?? String(decoding: Data(contentsOf: fixtures.appending(path: libraryFile)), as: UTF8.self))
            .replacingOccurrences(of: "library (fixture) {", with: "library (fixture) { operating_conditions(typical){process:1;voltage:1;temperature:25;} default_operating_conditions:typical;")
        let library = try helper.input(Data(text.utf8), name: "timing.lib", format: .liberty, root: root)
        var manifest = try PDKManifestCodec.decode(data: Data(contentsOf: fixtures.appending(path: "pdk.json")))
        manifest.assets[0].sha256 = library.digest.hexadecimalValue; manifest.assets[0].byteCount = Int64(library.byteCount)
        let pdk = try helper.input(PDKManifestCodec.encode(manifest), name: "pdk.json", format: .json, root: root)
        let sdc = try helper.input(Data((sdcText ?? """
        create_clock -name clk -period 10ns [get_ports p0_0]
        set_input_delay 1ns -clock clk [get_ports p0_0]
        set_output_delay -max 2ns -clock clk [get_ports p1_0]
        """).utf8), name: "constraints.sdc", format: .sdc, root: root)
        func binding(_ value: LogicArtifactBinding) throws -> TimingArtifactBinding {
            try .init(reference: value.reference, availability: value.availability)
        }
        let timing = try LogicSynthesisTimingConstraints(libraries: [.init(artifact: binding(library), cornerIDs: ["typical"])],
            constraints: binding(sdc), pdkManifest: binding(pdk), processID: manifest.processID, pdkVersion: manifest.version,
            cornerIDs: ["typical"], modeIDs: ["functional"], characterizationBindings: [.init(cornerID: "typical", conditionName: "typical")],
            minimumSetupSlack: requiredSlack, minimumHoldSlack: requiredHoldSlack, maximumPaths: 10)
        let source = try helper.input(Data((sourceText ?? "module top(input a,output y);assign y=\(expression);endmodule").utf8), name: "top.sv", format: .systemVerilog, root: root)
        return LogicEngineRuntime.LogicSynthesisRequest(runID: runID, sources: [.init(logicalName: "top.sv", artifact: source)],
            roots: ["top.sv"], top: "top", library: library, limits: helper.limits(), constraints: .init(timing: timing))
    }
    @Test func timingPrerequisitesHaveOneCanonicalInputReference() throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root)
        #expect(request.inputs.count == Set(request.inputs).count)
        #expect(request.inputs.filter { $0 == request.library.reference }.count == 1)
    }


    @Test func sourceAliasesAndBothConstantsSurviveActualProofSTASaveAndReload() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root, sourceText: "module top(input a,output [3:0] y);assign y={a,~a,1'b0,1'b1};endmodule",
            sdcText: "create_clock -name clk -period 10ns [get_ports p0_0]\nset_input_delay 1ns -clock clk [get_ports p0_0]\n"
                + (0..<4).map { "set_output_delay 2ns -clock clk [get_ports p1_\($0)]" }.joined(separator: "\n"))
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        let loaded = try await engine.load(result.receipt, limits: request.limits)
        try loaded.equivalence.requireBinding(to: loaded.problem)
        let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
        #expect(result.payload.instanceCount == 1)
        #expect(abs(try #require(sta.payload.worstSetupSlack) - 6e-9) < 1e-20)
        #expect(sta.payload.endpoints.filter { $0.staticValue != nil }.count == 2)
        #expect(Set(sta.payload.endpoints.compactMap(\.staticValue)) == [.zero, .one])
        #expect(sta.payload.unconstrainedEndpoints.isEmpty)
    }

    @Test func staticMinimumIsCheckedCoverageAndUnconstrainedTimingCannotPass() async throws {
        let helper = ActualCellRuntimeTests()
        for unknown in [false, true] {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, requiredSlack: 1,
                sourceText: unknown ? "module top(input a,output y,z);assign y=1'b0;assign z=a;endmodule"
                    : "module top(input a,output y);assign y=1'b0;endmodule")
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
            if unknown {
                await #expect(throws: LogicRuntimeError.self) { _ = try await engine.execute(request) }
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/native-sta/synthesis-receipt-v4.json").path))
            } else {
                let result = try await engine.execute(request)
                let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
                #expect(sta.payload.worstSetupSlack == nil && sta.payload.endpoints.allSatisfy { $0.staticChecks == [.setup] })
                _ = try await engine.load(result.receipt, limits: request.limits)
            }
        }
    }
    @Test func constantSequentialDataRetainsInductiveProofAndMeasuredClockToQ() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root, sourceText: "module top(input clk,output logic q);always_ff @(posedge clk) q<=1'b0;endmodule",
            libraryFile: "ff-timing.lib", requiredHoldSlack: 1)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        #expect(result.payload.proofKind == "state-preserving-induction-rup" && result.payload.instanceCount == 1)
        let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
        #expect(abs(try #require(sta.payload.worstSetupSlack) - 7.5e-9) < 1e-20)
        #expect(sta.payload.worstHoldSlack == nil)
        #expect(sta.payload.endpoints.contains { $0.staticValue == .zero && $0.staticChecks == [.setup, .hold] })
        let checked = try await engine.load(result.receipt, limits: request.limits)
        try checked.equivalence.requireBinding(to: checked.problem)
        let simulation = LogicEngineRuntime.LogicSimulationRequest(runID: "constant-d-events", mappedReceipt: result.receipt,
            events: [.init(time: 1, updates: [.init(portIndex: 0, value: "0")]),
                     .init(time: 2, updates: [.init(portIndex: 0, value: "1")])], limits: request.limits)
        let observed = try await LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store).execute(simulation)
        #expect(observed.observations.map { $0.outputs.first?.value } == ["x", "x", "0"])
    }
    @Test func numericSlackCannotHideAnUnconstrainedAlias() async throws {
        let helper = ActualCellRuntimeTests()
        for (y, z) in [("a", "a"), ("~a", "a"), ("a", "1'b0")] {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, sourceText: "module top(input a,output y,z);assign y=\(y);assign z=\(z);endmodule")
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
            await #expect(throws: LogicRuntimeError.self) { _ = try await engine.execute(request) }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/native-sta/synthesis-receipt-v4.json").path))
        }
    }
    @Test func sourceAliasesRetainEachDelayAndRejectPathExceptions() async throws {
        let helper = ActualCellRuntimeTests()
        for exception in ["", "set_max_delay -probe 0.5ns -from [get_ports p0_0] -to [get_ports p2_0]"] {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, sourceText: "module top(input a,output y,z);assign y=a;assign z=a;endmodule",
                sdcText: """
                create_clock -name clk -period 10ns [get_ports p0_0]
                set_input_delay 1ns -clock clk [get_ports p0_0]
                set_output_delay -max 2ns -clock clk [get_ports p1_0]
                set_output_delay 4ns -clock clk [get_ports p2_0]
                \(exception)
                """)
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
            if !exception.isEmpty {
                await #expect(throws: LogicRuntimeError.self) { _ = try await engine.execute(request) }
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/native-sta/synthesis-receipt-v4.json").path))
                continue
            }
            let result = try await engine.execute(request)
            let checked = try await engine.load(result.receipt, limits: request.limits)
            try checked.equivalence.requireBinding(to: checked.problem)
            let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
            #expect(abs(try #require(sta.payload.endpoints.first { $0.endpoint == "p1_0" }?.setupSlack) - 7e-9) < 1e-20)
            #expect(abs(try #require(sta.payload.endpoints.first { $0.endpoint == "p2_0" }?.setupSlack) - 5e-9) < 1e-20)
        }
    }
    @Test func absentHoldTableCannotBecomeAZeroMeasuredConstraint() async throws {
        let raw = String(decoding: try Data(contentsOf: #require(Bundle.module.resourceURL).appending(path: "Fixtures/ff-timing.lib")), as: UTF8.self)
        let hold = """
              timing () { related_pin : "CLK"; timing_type : hold_rising;
                rise_constraint (t) { index_1 ("0.1"); index_2 ("0.0"); values ("0.0"); }
                fall_constraint (t) { index_1 ("0.1"); index_2 ("0.0"); values ("0.0"); }
              }
        """
        #expect(raw.contains(hold))
        for observed in [true, false] {
            let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, sourceText: "module top(input clk,d,output logic q);always_ff @(posedge clk) q<=d;endmodule",
                sdcText: "create_clock -name clk -period 10ns [get_ports p0_0]\nset_input_delay 1ns -clock clk [get_ports p1_0]\nset_output_delay -max 2ns -clock clk [get_ports p2_0]\nset_output_delay -min 0ns -clock clk [get_ports p2_0]",
                libraryFile: "ff-timing.lib", libraryText: observed ? raw : raw.replacingOccurrences(of: hold, with: ""), requiredHoldSlack: 0)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
            if observed { _ = try await engine.execute(request) }
            else { await #expect(throws: LogicRuntimeError.self) { try await engine.execute(request) } }
        }
    }
    @Test func initializedQRemainsSourceStateAndCannotPassActualCellSTA() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root, sourceText: "module top(input clk,output bit q=1'b1);always_ff @(posedge clk) q<=1'b0;endmodule",
            libraryFile: "ff-timing.lib", requiredHoldSlack: 1)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        await #expect(throws: LogicRuntimeError.self) {
            try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store).execute(request)
        }
        let events: [LogicSimulationEventRecord] = [.init(time: 1, updates: [.init(portIndex: 0, value: "0")]),
                                                   .init(time: 2, updates: [.init(portIndex: 0, value: "1")])]
        let observed = try await LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store).execute(
            .init(runID: "source-events", sources: request.sources, roots: request.roots, top: request.top,
                  events: events, limits: request.limits))
        #expect(observed.observations.map { $0.outputs.first?.value } == ["1", "1", "0"])
    }
}
