import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicSimulation
import LogicLowering
import LogicProofProbeSupport
import LogicWordLoweringProbeSupport
import SystemVerilogFrontend

public enum DeclarationSemanticsContractProbe {
    private enum Fixture { case wide; case partial; case hierarchy; case wire; case defaultBit; case state; case guarded; case netInitializer; case inputClock; case partialWire }
    private static func source(_ fixture: Fixture) -> (String, String) {
        switch fixture {
        case .wide: return ("module p(input logic [128:0] a,output bit [128:0] y,output logic [128:0] seen);always_comb begin y=a;seen=y;end endmodule","803de2f5cefb21f5042a0b2bc2b659f1bc14a20d141642a7a34264034b8e897a")
        case .partial: return ("module p(input clk,input logic [3:0] d,output bit [3:0] q=4'b1010,output bit [3:0] r);always_ff @(posedge clk)begin q[2:1]<=d[1:0];r<=q;end endmodule","570c9691a5d8255b3634fe1bef295721c414a6aa23dcaba617e75fc92f896555")
        case .hierarchy: return ("module p(input logic a,output logic y,output bit b);child u(a,y);assign b=a;endmodule module child(input var bit a,output logic y);assign y=a;endmodule","e0d746342873245cb2a50c11f01b992595e2a88e28269f06815ec79180655840")
        case .wire: return ("module p(output wire [64:0] y,output bit [64:0] b,output logic [64:0] v);wire [64:0] a;assign y=a;endmodule","e12ef731a516eef27e3b9a921fcb0a7612b60eaee8bf19744a916d823a2df052")
        case .defaultBit: return ("module p(output bit [64:0] y);endmodule","4ae84560d46b8c521345cad2a29a8642ab82fa9173b85270c411cfd62b0bc9ef")
        case .state: return ("module p(input clk,input [3:0] d,output bit [3:0] q,output bit [3:0] e=4'b1010,output logic [3:0] r);always_ff @(posedge clk)begin q<=d;e<=d;r<=d;end endmodule","83f0ae655c716fd7b2513cd39ad5d477746a4d1fc2fa6ceb0ac272b73de4e0d1")
        case .guarded: return ("module p(input [1:0] a,input d,output bit t,output logic y);logic [2:0] i;always_comb begin i=4;t=a[i];if(t==0)y=d;else y=0;end endmodule","8f6182ffd769cb2324fc84baf1ec9036c83708e0de8db45603e8ecc43f554a70")
        case .netInitializer: return ("module p(input a,output wire y=a);endmodule","470714e9649d1152b19ca89f00b302c734eb52eae80e6a8f77e445c47100a7ae")
        case .inputClock: return ("module p(input var bit clk,input logic d,output bit q);always_ff @(posedge clk)q<=d;endmodule","54d5394de27655c6cf7ee533f55daa72f04927fefbe1a3f11a5df07004863955")
        case .partialWire: return ("module p(input [1:0] a,output wire [3:0] y);assign y[1:0]=a;endmodule","e3c0a325d96d15cec2c72aeb722b025d7263dbe74997a97b4136f323221525d5")
        }
    }
    private static func elaborate(_ fixture: Fixture, context: inout LogicKernelContext) throws(LogicKernelError) -> ElaboratedRTL {
        let (text, digest) = source(fixture); let bytes = Array(text.utf8)
        let artifact: ArtifactID
        do { artifact = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: digest), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidInput("Declaration fixture identity is invalid") }
        let document = try LogicSourceDocument(logicalName: "p.sv", artifactID: artifact, bytes: bytes, context: &context)
        let bundle = try LogicSourceBundle(documents: [document], context: &context)
        let frontend: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
        return try frontend.elaborate(bundle, options: SourceLoweringContractProbe.options(["p.sv"]), context: &context)
    }
    private static func vector(_ word: UInt64, width: Int = 1, unknowns: UInt64 = 0) throws(LogicKernelError) -> LogicFourStateVector {
        try .init(width: .init(width), valueWords: [word], unknownWords: [unknowns])
    }
    private static func require(_ actual: borrowing LogicFourStateVector, bits: [LogicBit]) throws(LogicKernelError) {
        guard actual.width.value == bits.count else { throw .invalidModel("Declaration observation width changed") }
        for bit in bits.indices {
            guard try actual.bit(at: bit) == bits[bit] else { throw .invalidModel("Declaration observation differs from language semantics") }
        }
    }
    private static func outputs(_ graph: borrowing BitLogicDesign, inputs: [Bool]) -> [Bool] {
        let values = LogicOptimizationContractProbe.values(graph, inputs: inputs)
        return graph.withTables { _, _, ports, bindings, _, _ in
            var result: [Bool] = []
            for port in ports.indices where ports[port].direction == .output {
                for bit in ports[port].bits { result.append(values[bindings[bit].rawValue]) }
            }
            return result
        }
    }
    private static func lower(_ rtl: borrowing ElaboratedRTL, context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        let wordKernel: any LogicWordLowering = NativeLogicWordLowering()
        let word = try wordKernel.lower(rtl, context: &context)
        let bitKernel: any LogicBitLowering = NativeLogicBitLowering()
        return try bitKernel.lower(word, context: &context)
    }
    public static func wideBlockingConversion() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.wide, context: &context)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
        var state = try evaluator.makeState(model, context: &context)
        for offset in 0..<4 {
            var values = [UInt64](repeating: 0, count: 3); var unknowns = values
            var expected: [LogicBit] = []
            for bit in 0..<129 {
                let digit = (bit + offset) % 4
                values[bit / 64] |= UInt64(digit & 1) << (bit % 64)
                unknowns[bit / 64] |= UInt64(digit >> 1) << (bit % 64)
                expected.append(digit == 1 ? .one : .zero)
            }
            let value = try LogicFourStateVector(width: .init(129), valueWords: values, unknownWords: unknowns)
            let observed = try evaluator.evaluate(model, event: .init(time: UInt64(offset), updates: [.init(portIndex: 0, value: value)]), state: &state, context: &context)
            for port in 0..<2 { try require(observed.output(at: port).value, bits: expected) }
        }
        let graph = try lower(rtl, context: &context)
        for digit in [false,true] {
            let observed = outputs(graph, inputs: [Bool](repeating: digit, count: 129))
            guard observed == [Bool](repeating: digit, count: 258) else { throw .invalidModel("Binary bit writes changed lowering behavior") }
        }
    }
    public static func partialNBAAndSampling() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.partial, context: &context)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
        var state = try evaluator.makeState(model, context: &context)
        let initial = try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &context)
        try require(initial.output(at: 0).value, bits: [.zero,.one,.zero,.one])
        try require(initial.output(at: 1).value, bits: [.zero,.zero,.zero,.zero])
        for (clock, expectedQ, expectedR) in [(0,10,0),(1,8,10),(0,8,10),(1,8,8)] {
            let observed = try evaluator.evaluate(model, event: .init(time: 0, updates: [
                .init(portIndex: 0, value: vector(UInt64(clock))),
                .init(portIndex: 1, value: vector(1,width: 4,unknowns: 15))]), state: &state, context: &context)
            guard try observed.output(at: 0).value.binaryInt(signed: false, context: &context) == expectedQ,
                  try observed.output(at: 1).value.binaryInt(signed: false, context: &context) == expectedR else {
                throw .invalidModel("Partial NBA conversion or old-value sampling changed")
            }
        }
        _ = try lower(rtl, context: &context)
    }
    public static func hierarchyAndContinuousConversion() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.hierarchy, context: &context)
        guard rtl.signalCount == 5 else { throw .invalidModel("Hierarchy aliased across value domains") }
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
        var state = try evaluator.makeState(model, context: &context)
        for digit in 0..<4 {
            let observed = try evaluator.evaluate(model, event: .init(time: UInt64(digit), updates: [
                .init(portIndex: 0, value: vector(UInt64(digit & 1),unknowns: UInt64(digit >> 1)))]), state: &state, context: &context)
            for port in 0..<2 { try require(observed.output(at: port).value, bits: [digit == 1 ? .one : .zero]) }
        }
        let graph = try lower(rtl, context: &context)
        for digit in [false,true] {
            guard outputs(graph, inputs: [digit]) == [digit,digit] else {
                throw .invalidModel("Typed hierarchy binary lowering changed")
            }
        }
    }
    public static func undrivenNetAndVariableDefaults() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.wire, context: &context)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
        var state = try evaluator.makeState(model, context: &context)
        let observed = try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &context)
        for (port, digit): (Int,LogicBit) in [(0,.highImpedance),(1,.zero),(2,.unknown)] {
            try require(observed.output(at: port).value, bits: [LogicBit](repeating: digit, count: 65))
        }
        do throws(LogicKernelError) { _ = try lower(rtl, context: &context); throw .invalidModel("Observed Z was silently lowered") }
        catch let error {
            guard case .sourceFailure(_, let origin, _) = error, !origin.byteRange.isEmpty else { throw error }
        }
        let binaryRTL = try elaborate(.defaultBit, context: &context)
        let binary = try lower(binaryRTL, context: &context)
        guard outputs(binary, inputs: []) == [Bool](repeating: false, count: 65) else {
            throw .invalidModel("Undriven two-state variable did not lower to zero")
        }
    }
    public static func stateInitialRanges() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.state, context: &context)
        let word = try NativeLogicWordLowering().lower(rtl, context: &context)
        try word.withTables { _, _, _, states, _ throws(LogicKernelError) in
            guard states.count == 12 else { throw .invalidModel("Word state bits changed") }
            for bit in states.indices {
                let expected: LogicBit? = bit < 4 ? .zero : bit < 8 ? ((bit - 4) % 2 == 1 ? .one : .zero) : nil
                guard try states[bit].initialValue?.bit(at: 0) == expected else { throw .invalidModel("Word initial-state domain changed") }
            }
        }
        let graph = try NativeLogicBitLowering().lower(word, context: &context)
        try graph.withTables { _, _, _, _, states, _ throws(LogicKernelError) in
            for bit in states.indices {
                let expected: Bool? = bit < 4 ? false : bit < 8 ? (bit - 4) % 2 == 1 : nil
                guard states[bit].initialValue == expected else { throw .invalidModel("Bit initial-state domain changed") }
            }
        }
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &context)
        let initial = try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &context)
        try require(initial.output(at: 0).value, bits: [.zero,.zero,.zero,.zero])
        try require(initial.output(at: 1).value, bits: [.zero,.one,.zero,.one])
        try require(initial.output(at: 2).value, bits: [.unknown,.unknown,.unknown,.unknown])
    }
    public static func convertedLocalControlsQualifyActualBranches() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.guarded, context: &context)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &context)
        for digit in 0...1 {
            let observed = try evaluator.evaluate(model, event: .init(time: UInt64(digit), updates: [
                .init(portIndex: 0, value: vector(0,width: 2)),.init(portIndex: 1, value: vector(UInt64(digit)))]), state: &state, context: &context)
            try require(observed.output(at: 0).value, bits: [.zero])
            try require(observed.output(at: 1).value, bits: [digit == 1 ? .one : .zero])
        }
    }
    public static func netInitializersRemainLiveDrivers() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.netInitializer, context: &context)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &context)
        for digit in 0...1 {
            let observed = try evaluator.evaluate(model, event: .init(time: UInt64(digit), updates: [
                .init(portIndex: 0, value: vector(UInt64(digit)))]), state: &state, context: &context)
            try require(observed.output(at: 0).value, bits: [digit == 1 ? .one : .zero])
        }
        let graph = try lower(rtl, context: &context)
        for digit in [false,true] {
            guard outputs(graph, inputs: [digit]) == [digit] else { throw .invalidModel("Net initializer became frozen initial state") }
        }
    }
    public static func inputConversionPrecedesClockEdgeDetection() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.inputClock, context: &context)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &context)
        for (clock, data, expected) in [(2,1,0),(3,1,0),(1,1,1),(2,0,1),(3,0,1),(1,0,0)] {
            let observed = try evaluator.evaluate(model, event: .init(time: 0, updates: [
                .init(portIndex: 0, value: vector(UInt64(clock & 1),unknowns: UInt64(clock >> 1))),
                .init(portIndex: 1, value: vector(UInt64(data)))]), state: &state, context: &context)
            try require(observed.output(at: 0).value, bits: [expected == 1 ? .one : .zero])
        }
    }
    public static func unwrittenNetBitsStayHighImpedance() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let rtl = try elaborate(.partialWire, context: &context)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &context)
        for digit in 0..<4 {
            let observed = try evaluator.evaluate(model, event: .init(time: UInt64(digit), updates: [
                .init(portIndex: 0, value: vector(UInt64(digit),width: 2))]), state: &state, context: &context)
            try require(observed.output(at: 0).value, bits: [digit & 1 == 0 ? .zero : .one,digit & 2 == 0 ? .zero : .one,.highImpedance,.highImpedance])
        }
    }
    public static func exercise() throws(LogicKernelError) {
        try wideBlockingConversion(); try partialNBAAndSampling(); try hierarchyAndContinuousConversion()
        try undrivenNetAndVariableDefaults(); try stateInitialRanges(); try convertedLocalControlsQualifyActualBranches()
        try netInitializersRemainLiveDrivers(); try inputConversionPrecedesClockEdgeDetection(); try unwrittenNetBitsStayHighImpedance()
    }
}
