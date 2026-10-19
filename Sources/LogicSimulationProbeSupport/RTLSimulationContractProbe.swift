import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicSimulation
import SystemVerilogFrontend

public enum RTLSimulationContractProbe {
    public static func elaborate(_ text: String, digestHex: String, context: inout LogicKernelContext) throws(LogicKernelError) -> ElaboratedRTL {
        let bytes = Array(text.utf8)
        let identity: ArtifactID
        do { identity = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: digestHex), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidInput("Probe source identity is invalid") }
        let document = try LogicSourceDocument(logicalName: "p.sv", artifactID: identity, bytes: bytes, context: &context)
        let bundle = try LogicSourceBundle(documents: [document], context: &context)
        let options = try SystemVerilogElaborationOptions(roots: ["p.sv"], top: "p", maximumTokens: 4000,
            syntax: .init(nodes: 2000, children: 4000, symbols: 1000, nesting: 60),
            rtl: .init(signals: 100, expressions: 2000, operands: 4000, statements: 1000, children: 2000,
                caseItems: 100, caseMatches: 200, ports: 20, processes: 100), maximumNesting: 60)
        let frontend: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
        return try frontend.elaborate(bundle, options: options, context: &context)
    }
    private static func exerciseAdmission(context: inout LogicKernelContext) throws(LogicKernelError) {
        do {
            let text = "module p(input d,output logic q,r);wire a;always_comb begin q=a;r=d;end assign a=r;endmodule"
            let rtl = try elaborate(text, digestHex: "74423a6ac4af57e55a0a3028856101646b058187f05a47ec2b2be7c23b64f1cc", context: &context)
            let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
            let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
            var state = try evaluator.makeState(model, context: &context)
            for bit in [LogicBit.zero, .one, .unknown, .highImpedance] {
                let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [
                    .init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(bit, context: &context))]), state: &state, context: &context)
                guard try output.output(at: 0).value.bit(at: 0) == bit, try output.output(at: 1).value.bit(at: 0) == bit else {
                    throw .invalidModel("Independent RTL outputs acquired a false cycle or wrong value")
                }
            }
        }
        do {
            let text = "module p(input en,sel,d,output logic q,r);always_latch if(en)begin if(sel)q=d;else q=~d;end always_latch if(en)r=d;endmodule"
            let rtl = try elaborate(text, digestHex: "6e4498db85c7d8d8d6eb76c95c3ae5b60c74fa81ff3a725aed61420223ef1385", context: &context)
            let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
            let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
            var state = try evaluator.makeState(model, context: &context)
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [
                .init(portIndex: 0, value: LogicSimulationProbeFixtures.vector(.one, context: &context)),
                .init(portIndex: 1, value: LogicSimulationProbeFixtures.vector(.zero, context: &context)),
                .init(portIndex: 2, value: LogicSimulationProbeFixtures.vector(.one, context: &context))]), state: &state, context: &context)
            guard try output.output(at: 0).value.bit(at: 0) == .zero, try output.output(at: 1).value.bit(at: 0) == .one else {
                throw .invalidModel("Canonical latch write gate changed event behavior")
            }
        }
    }

    public static func exercise() throws(LogicKernelError) {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        try exerciseAdmission(context: &run)
        let text = "module p(input clk,rn,input [1:0] d,output logic [1:0] q,r);always_ff @(posedge clk or negedge rn) if(!rn)begin q<=0;r<=0;end else begin q<=d;r<=q;end endmodule"
        let rtl = try elaborate(text, digestHex: "5f7c940faf3c923a19f761012c826dacb28114d45053903a252fe47e6c15de0b", context: &run)
        let compiler: any LogicSimulationCompiling = NativeLogicSimulationCompiler()
        let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
        let model = try compiler.compile(rtl, context: &run)
        var state = try evaluator.makeState(model, context: &run)
        for (clock, reset, data, q, r) in [(0,0,3,0,0),(0,1,3,0,0),(1,1,3,3,0),(0,1,1,3,0),(1,1,1,1,3)] {
            let updates = try [LogicInputEvent.Update(portIndex: 0, value: .init(repeating: clock == 0 ? .zero : .one, width: .init(1), context: &run)),
                .init(portIndex: 1, value: .init(repeating: reset == 0 ? .zero : .one, width: .init(1), context: &run)),
                .init(portIndex: 2, value: .init(width: .init(2), valueWords: [UInt64(data)], unknownWords: [0]))]
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: updates), state: &state, context: &run)
            guard try output.output(at: 0).value.binaryInt(signed: false, context: &run) == q,
                  try output.output(at: 1).value.binaryInt(signed: false, context: &run) == r else {
                throw .invalidModel("RTL NBA pipeline did not sample simultaneously")
            }
        }
    }
}
