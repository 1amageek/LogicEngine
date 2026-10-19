import Foundation
import LogicEngineCore
import LogicEngineRuntime
import STAEngine
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ActualCellPathExceptionTests {
    static let cases: [(String, String, Double?, Double?, Double?, Double?)] = [
        ("false", "set_false_path -to [get_ports p1_0]", nil, nil, 6e-9, 2e-9),
        ("all-false", "set_false_path -to [get_ports {p1_0 p2_0}]", nil, nil, nil, nil),
        ("multicycle", "set_multicycle_path -setup 2 -to [get_ports p1_0]\nset_multicycle_path -hold 1 -to [get_ports p1_0]", 16e-9, 2e-9, 6e-9, 2e-9),
        ("max", "set_max_delay 5ns -to [get_ports p1_0]", 1e-9, 2e-9, 6e-9, 2e-9),
        ("min", "set_min_delay 1ns -to [get_ports p1_0]", 6e-9, 1e-9, 6e-9, 2e-9)
    ]
    static let base = """
    create_clock -name clk -period 10ns [get_ports p0_0]
    set_input_delay 1ns -clock clk [get_ports p0_0]
    set_output_delay -max 2ns -clock clk [get_ports {p1_0 p2_0}]
    set_output_delay -min 0ns -clock clk [get_ports {p1_0 p2_0}]
    """
    func request(root: URL, clause: String, runID: String = "path-exception", excluded: Bool = false) throws -> LogicEngineRuntime.LogicSynthesisRequest {
        try ActualCellTimingTests().request(root: root, requiredSlack: excluded ? 1 : 0, runID: runID,
            sourceText: "module top(input a,output y,z);assign y=~a;assign z=y;endmodule",
            sdcText: Self.base + "\n" + clause, requiredHoldSlack: excluded ? 1 : 0)
    }
    static func check(_ actual: Double?, _ expected: Double?) {
        if let expected, let actual { #expect(abs(actual - expected) < 1e-20) }
        else { #expect(actual == nil && expected == nil) }
    }
    static func check(_ sta: STAExecutionResult, row: (String, String, Double?, Double?, Double?, Double?)) throws {
        #expect(sta.status == .completed && sta.payload.unconstrainedEndpoints.isEmpty)
        let y = try #require(sta.payload.endpoints.first { $0.endpoint == "p1_0" })
        let z = try #require(sta.payload.endpoints.first { $0.endpoint == "p2_0" })
        check(y.setupSlack, row.2); check(y.holdSlack, row.3); check(z.setupSlack, row.4); check(z.holdSlack, row.5)
        if row.0.contains("false") {
            #expect(y.excludedChecks == [.setup, .hold] && y.staticValue == nil && y.staticChecks == nil)
            #expect(!sta.payload.criticalPaths.contains { $0.endpoint == "p1_0" })
        }
    }
    @Test func allFourExceptionsRetainAliasProofSTAAndCheckedReload() async throws {
        let helper = ActualCellRuntimeTests()
        for row in Self.cases {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, clause: row.1, excluded: row.0 == "all-false")
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
            let result = try await engine.execute(request)
            #expect(result.payload.instanceCount == 1 && result.payload.proofKind == "combinational-rup")
            let checked = try await engine.load(result.receipt, limits: request.limits)
            try checked.equivalence.requireBinding(to: checked.problem)
            let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(#require(result.payload.timingResult)))
            try Self.check(sta, row: row)
            if row.0 == "all-false" {
                let simulated = try await LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store).execute(
                    .init(runID: "excluded-functional-events", mappedReceipt: result.receipt,
                        events: [.init(time: 1, updates: [.init(portIndex: 0, value: "0")]),
                                 .init(time: 2, updates: [.init(portIndex: 0, value: "1")])], limits: request.limits))
                #expect(simulated.observations.map { $0.outputs.first?.value } == ["x", "1", "0"])
            }
        }
    }
    @Test func negativeMinDelayAndUnsupportedOptionsPublishNoReceipt() async throws {
        let helper = ActualCellRuntimeTests()
        for clause in ["set_min_delay 3ns -to [get_ports p1_0]", "set_false_path -rise_to [get_ports p1_0]",
                       "set_false_path -to [get_ports absent]"] {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, clause: clause)
            await #expect(throws: LogicRuntimeError.self) {
                _ = try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)).execute(request)
            }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/path-exception/synthesis-receipt-v4.json").path))
        }
    }
}
