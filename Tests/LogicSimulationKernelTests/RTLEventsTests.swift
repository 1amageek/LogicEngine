import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import LogicIR
import LogicKernelCore
import LogicSimulation
import LogicSimulationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct RTLEventsTests {
    private func compile(_ text: String, context: inout LogicKernelContext) throws -> LogicSimulationModel {
        let bytes = Array(text.utf8)
        let digest = try SHA256ContentDigester().digest(using: .sha256,
            limits: .init(maximumChunkByteCount: UInt64(bytes.count), maximumTotalByteCount: UInt64(bytes.count), maximumUpdateCount: 1)) {
                lease throws(ContentDigestError) in try lease.update(bytes)
            }
        let rtl = try RTLSimulationContractProbe.elaborate(text, digestHex: digest.digest.hexadecimalValue, context: &context)
        return try NativeLogicSimulationCompiler().compile(rtl, context: &context)
    }
    @Test func sourceFFPipelineSamplesAndPublishesNBA() throws { try RTLSimulationContractProbe.exercise() }
    @Test func blockingStatementsAndAssignmentGroupsReadTheRightEnvironment() throws {
        for body in ["q=d; q=q+1;", "{q[0],q[1]}=d;"] {
            var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
            let model = try compile("module p(input [1:0] d,output logic [1:0] q);always_comb begin \(body) end endmodule", context: &run)
            let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
            for data in 0..<4 {
                let input = try LogicFourStateVector(width: .init(2), valueWords: [UInt64(data)], unknownWords: [0])
                let result = try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: input)]), state: &state, context: &run)
                #expect(try result.output(at: 0).value.binaryInt(signed: false, context: &run) == (body.hasPrefix("q=") ? (data + 1) % 4 : ((data & 1) << 1) | (data >> 1)))
            }
        }
    }
    @Test func zAssignmentsAndFourStateCaseAreNotBinaryLowering() throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let model = try compile("module p(input [1:0] a,output logic y,output wire [1:0] z);assign z=a;always_comb case(a)2'b01:y=1'b1;default:y=1'b0;endcase endmodule", context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        let input = try LogicFourStateVector(width: .init(2), valueWords: [1], unknownWords: [3])
        let result = try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: input)]), state: &state, context: &run)
        #expect(try result.output(at: 0).value.bit(at: 0) == .zero)
        #expect(try result.output(at: 1).value.bit(at: 0) == .highImpedance)
        #expect(try result.output(at: 1).value.bit(at: 1) == .unknown)
    }
    @Test func latchTransparencyHoldAndUnknownInitialization() throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let model = try compile("module p(input en,d,output logic q);always_latch if(en) q<=d;endmodule", context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        let initial = try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &run)
        #expect(try initial.output(at: 0).value.bit(at: 0) == .unknown)
        for (en, data, expected) in [(1,1,1),(0,0,1),(1,0,0)] {
            let updates = try [LogicInputEvent.Update(portIndex: 0, value: LogicSimulationProbeFixtures.vector(en == 0 ? .zero : .one, context: &run)),
                .init(portIndex: 1, value: LogicSimulationProbeFixtures.vector(data == 0 ? .zero : .one, context: &run))]
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: updates), state: &state, context: &run)
            #expect(try output.output(at: 0).value.bit(at: 0) == (expected == 0 ? .zero : .one))
        }
    }
    @Test func transparentCyclesAndCrossFFBlockingRacesAreRefused() throws {
        for text in ["module p(input en,output logic q);always_latch if(en) q=~q;endmodule",
                     "module p(input clk,d,output logic q,r);always_ff @(posedge clk) q=d;always_ff @(posedge clk) r<=q;endmodule"] {
            var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
            #expect(throws: LogicKernelError.self) { try compile(text, context: &run) }
        }
    }
}

