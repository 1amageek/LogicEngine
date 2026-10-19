import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import LogicIR
import LogicKernelCore
import LogicSimulation
import LogicSimulationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct RTLDependencyAdmissionTests {
    private func compile(_ text: String, context: inout LogicKernelContext) throws -> LogicSimulationModel {
        let bytes = Array(text.utf8)
        let digest = try SHA256ContentDigester().digest(using: .sha256,
            limits: .init(maximumChunkByteCount: UInt64(bytes.count), maximumTotalByteCount: UInt64(bytes.count), maximumUpdateCount: 1)) {
                lease throws(ContentDigestError) in try lease.update(bytes)
            }
        let rtl = try RTLSimulationContractProbe.elaborate(text, digestHex: digest.digest.hexadecimalValue, context: &context)
        return try NativeLogicSimulationCompiler().compile(rtl, context: &context)
    }
    @Test func independentProcessOutputsAndOrderedPartialWritesAreNotCycles() throws {
        for text in [
            "module p(input d,output logic q,r);wire a;always_comb begin q=a;r=d;end assign a=r;endmodule",
            "module p(input d,output logic [1:0] q);always_comb begin q[0]=d;q[1]=q[0];end endmodule"] {
            var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
            let model = try compile(text, context: &run)
            let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
            for bit in [LogicBit.zero, .one, .highImpedance] {
                let value = try LogicSimulationProbeFixtures.vector(bit, context: &run)
                let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: value)]), state: &state, context: &run)
                let q = try output.output(at: 0).value
                for index in 0..<q.width.value { #expect(try q.bit(at: index) == bit) }
            }
        }
    }
    @Test func finalNBAPriorityRemovesOverwrittenFeedback() throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let model = try compile("module p(input en,d,output logic q);always_comb begin q=q;if(en)q<=d;else q=d;end endmodule", context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        for en in [LogicBit.zero, .one, .unknown] {
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [
                .init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(en, context: &run)),
                .init(portIndex: 1, value: LogicSimulationProbeFixtures.vector(.one, context: &run))]), state: &state, context: &run)
            #expect(try output.output(at: 0).value.bit(at: 0) == .one)
        }
    }
    @Test func restoredBranchesDoNotReuseTheOtherEnvironment() throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let model = try compile("module p(input en,d,output logic q,r);always_comb begin q=d;if(en)q=~q;else q=q;r=q;end endmodule", context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        for (en, expected) in [(LogicBit.one, LogicBit.zero), (.zero, .one), (.unknown, .one)] {
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [
                .init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(en, context: &run)),
                .init(portIndex: 1, value: LogicSimulationProbeFixtures.vector(.one, context: &run))]), state: &state, context: &run)
            #expect(try output.output(at: 0).value.bit(at: 0) == expected)
            #expect(try output.output(at: 1).value.bit(at: 0) == expected)
        }
    }
    @Test func sameLatchGateSurvivesCompleteNestedDataConditions() throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let model = try compile("module p(input en,sel,d,output logic q,r);always_latch if(en)begin if(sel)q=d;else q=~d;end always_latch if(en)r=d;endmodule", context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [
            .init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(.one, context: &run)),
            .init(portIndex: 1, value: LogicSimulationProbeFixtures.vector(.zero, context: &run)),
            .init(portIndex: 2, value: LogicSimulationProbeFixtures.vector(.one, context: &run))]), state: &state, context: &run)
        #expect(try output.output(at: 0).value.bit(at: 0) == .zero)
        #expect(try output.output(at: 1).value.bit(at: 0) == .one)
    }
    @Test func profileAndActualBitFeedbackAreRefused() throws {
        for (text, reason) in [
            ("module p(input en,d,output logic q);always_comb if(en)q=d;endmodule", "every path"),
            ("module p(input a,b,d,output logic q,r);always_latch if(a)q=d;always_latch if(b)r=d;endmodule", "one canonical"),
            ("module p(input en,d,output logic q,r);always_latch if(en)q=d;always_latch if(!en)r=d;endmodule", "one canonical"),
            ("module p(input clk,en,d,output logic q,r);always_ff @(posedge clk)q<=d;always @* if(en)r=d;endmodule", "mix FF"),
            ("module p(input d,output logic [1:0]q);always_comb begin q[0]=d;q[1]=q[1];end endmodule", "cycle")] {
            var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
            do { _ = try compile(text, context: &run); Issue.record("Unsupported RTL was admitted") }
            catch LogicKernelError.unsupported(let message) { #expect(message.contains(reason)) }
        }
    }

    @Test func constantControlPrunesUnreachableFeedback() throws {
        for body in ["if(1'b0|1'b0)q=q;else q=d;", "case(1'b1)1'b0:q=q;default:q=d;endcase", "case(1'b1)1'b0:q<=q;default:q<=d;endcase q=q;", "if(q)q=d;else q=d;"] {
            var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
            let model = try compile("module p(input d,output logic q);always_comb begin \(body) end endmodule", context: &run)
            let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(.one, context: &run))]), state: &state, context: &run)
            #expect(try output.output(at: 0).value.bit(at: 0) == .one)
        }
    }
    @Test func failedRTLEventPoisonsStateAndRestartIsExplicit() throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let model = try compile("module p(input d,output wire q);assign q=d;endmodule", context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        var exhausted = try LogicSimulationProbeFixtures.context(limit: 1)
        #expect(throws: LogicKernelError.self) { try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &exhausted) }
        #expect(throws: LogicKernelError.self) { try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &run) }
        var restarted = try evaluator.makeState(model, context: &run)
        #expect(try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(.highImpedance, context: &run))]), state: &restarted, context: &run).output(at: 0).value.bit(at: 0) == .highImpedance)
    }

    @Test func immutableModelRunsConcurrentlyWithExclusiveStates() async throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let model = try compile("module p(input d,output logic q,r);wire a;always_comb begin q=a;r=d;end assign a=r;endmodule", context: &run)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for task in 0..<8 {
                group.addTask {
                    var context = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
                    let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &context)
                    for step in 0..<64 {
                        let bit = (step + task) % 2 == 0 ? LogicBit.zero : .one
                        let output = try evaluator.evaluate(model, event: .init(time: UInt64(step), updates: [
                            .init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(bit, context: &context))]), state: &state, context: &context)
                        #expect(try output.output(at: 0).value.bit(at: 0) == bit)
                        #expect(try output.output(at: 1).value.bit(at: 0) == bit)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

}
