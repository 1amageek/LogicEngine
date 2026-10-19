import Foundation
import LogicEngineCore
import LogicEngineRuntime
import LogicKernelCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ActualCellEventTests {
    @Test func sourceDeclarationDefaultsAndFourStateCoercionArePreserved() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let source = "module top(input logic a,output bit b,output logic l,output wire w);assign b=a;endmodule"
        let binding = try helper.input(Data(source.utf8), name: "top.sv", format: .systemVerilog, root: root)
        let request = LogicEngineRuntime.LogicSimulationRequest(runID: "events", sources: [.init(logicalName: "top.sv", artifact: binding)],
            roots: ["top.sv"], top: "top", events: [.init(time: 1, updates: [.init(portIndex: 0, value: "z")]),
                .init(time: 2, updates: [.init(portIndex: 0, value: "1")])], limits: helper.limits())
        let engine: any LogicEngineRuntime.LogicSimulationExecuting = LogicEngineRuntime.NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let result = try await engine.execute(request)
        #expect(result.observations.map { $0.outputs.map(\.value) } == [["0", "x", "z"], ["0", "x", "z"], ["1", "x", "z"]])
        #expect(result.artifactBindings.count == 3)
        for event in [LogicSimulationEventRecord(time: 1, updates: [.init(portIndex: 0, value: "11")]),
                      .init(time: 1, updates: [.init(portIndex: 0, value: "?")]),
                      .init(time: 1, updates: [.init(portIndex: 0, value: "0"), .init(portIndex: 0, value: "1")])] {
            let invalid = LogicEngineRuntime.LogicSimulationRequest(runID: "bad-event", sources: request.sources, roots: request.roots,
                top: request.top, events: [event], limits: request.limits)
            await #expect(throws: (any Error).self) { try await engine.execute(invalid) }
        }
    }
    @Test func actualCellSimulationLoadsCheckedReceiptAndEvaluatesPhysicalFunctions() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let synthesis = try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store).execute(helper.request(root: root))
        let request = LogicEngineRuntime.LogicSimulationRequest(runID: "mapped-events", mappedReceipt: synthesis.receipt,
            events: [.init(time: 1, updates: [.init(portIndex: 0, value: "10101010"), .init(portIndex: 1, value: "11001100")])], limits: helper.limits())
        let result = try await LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store).execute(request)
        #expect(result.observations.last?.outputs.first?.value == "10001000")
    }
}
