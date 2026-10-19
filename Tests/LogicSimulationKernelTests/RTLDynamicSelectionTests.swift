import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import LogicIR
import LogicKernelCore
import LogicSimulation
import LogicSimulationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct RTLDynamicSelectionTests {
    @Test func unknownOutOfRangeAndNegativeOffsetsProduceX() throws {
        var run = try LogicSimulationProbeFixtures.context(limit: 100_000_000)
        let text = "module p(input [1:0] a,input signed [2:0] i,output wire q);assign q=a[i];endmodule"
        let bytes = Array(text.utf8)
        let digest = try SHA256ContentDigester().digest(using: .sha256,
            limits: .init(maximumChunkByteCount: UInt64(bytes.count), maximumTotalByteCount: UInt64(bytes.count), maximumUpdateCount: 1)) {
                lease throws(ContentDigestError) in try lease.update(bytes)
            }
        let rtl = try RTLSimulationContractProbe.elaborate(text, digestHex: digest.digest.hexadecimalValue, context: &run)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        let data = try LogicFourStateVector(width: .init(2), valueWords: [1], unknownWords: [0])
        for (value, unknown, expected) in [(0,0,LogicBit.one),(1,0,.zero),(2,0,.unknown),(7,0,.unknown),(0,1,.unknown),(1,1,.unknown)] {
            let index = try LogicFourStateVector(width: .init(3), valueWords: [UInt64(value)], unknownWords: [UInt64(unknown)])
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: data), .init(portIndex: 1, value: index)]), state: &state, context: &run)
            #expect(try output.output(at: 0).value.bit(at: 0) == expected)
        }
    }
}
