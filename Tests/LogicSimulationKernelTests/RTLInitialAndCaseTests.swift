import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import LogicIR
import LogicKernelCore
@testable import LogicSimulation
import LogicSimulationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct RTLInitialAndCaseTests {
    @Test func explicitInitialZAndUnknownArePreserved() throws {
        for initial in [LogicBit.highImpedance, .one, .unknown] {
            var run = try LogicSimulationProbeFixtures.context()
            var builder = try ElaboratedRTLBuilder(topModuleID: .init(rawValue: 1), capacity: .init(signals: 1, expressions: 0, operands: 0, statements: 0, children: 0, caseItems: 0, caseMatches: 0, ports: 1, processes: 0), context: &run)
            let signal = try builder.addSignal(.init(id: .init(rawValue: 2), type: .init(width: .init(1)), initialValue: .init(repeating: initial, width: .init(1), context: &run)), context: &run)
            try builder.addPort(.init(id: .init(rawValue: 3), name: "q", direction: .output, signal: signal), context: &run)
            let rtl = try builder.finish(context: &run)
            let model = try NativeLogicSimulationCompiler().compile(rtl, context: &run)
            let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &run)
            #expect(try output.output(at: 0).value.bit(at: 0) == initial)
        }
    }
    @Test func ordinaryCaseMatchesXZExactlyInElaboratedRTL() throws {
        var run = try LogicSimulationProbeFixtures.context()
        var builder = try ElaboratedRTLBuilder(topModuleID: .init(rawValue: 1), capacity: .init(signals: 2, expressions: 4, operands: 0, statements: 3, children: 0, caseItems: 1, caseMatches: 1, ports: 2, processes: 1), context: &run)
        let vector = try WordLogicType(width: .init(2)); let scalar = try WordLogicType(width: .init(1))
        let input = try builder.addSignal(.init(id: .init(rawValue: 2), type: vector, isInput: true), context: &run)
        let output = try builder.addSignal(.init(id: .init(rawValue: 3), type: scalar), context: &run)
        let read = try builder.addExpression(id: .init(rawValue: 4), type: vector, operation: .read(input), context: &run)
        let xz = try LogicFourStateVector(width: .init(2), valueWords: [1], unknownWords: [3])
        let match = try builder.addExpression(id: .init(rawValue: 5), type: vector, operation: .constant(xz), context: &run)
        let one = try builder.addExpression(id: .init(rawValue: 6), type: scalar, operation: .constant(.init(repeating: .one, width: .init(1), context: &run)), context: &run)
        let zero = try builder.addExpression(id: .init(rawValue: 7), type: scalar, operation: .constant(.init(repeating: .zero, width: .init(1), context: &run)), context: &run)
        let yes = try builder.addStatement(.init(id: .init(rawValue: 8), operation: .assignment(target: output, selection: 0..<1, value: one, timing: .blocking)), context: &run)
        let no = try builder.addStatement(.init(id: .init(rawValue: 9), operation: .assignment(target: output, selection: 0..<1, value: zero, timing: .blocking)), context: &run)
        _ = try builder.addCaseItem(matches: [match], body: yes, context: &run)
        let root = try builder.addStatement(.init(id: .init(rawValue: 10), operation: .caseStatement(selector: read, items: 0..<1, defaultBody: no)), context: &run)
        try builder.addProcess(.init(id: .init(rawValue: 11), control: .combinational, body: root), context: &run)
        try builder.addPort(.init(id: .init(rawValue: 12), name: "a", direction: .input, signal: input), context: &run)
        try builder.addPort(.init(id: .init(rawValue: 13), name: "y", direction: .output, signal: output), context: &run)
        let rtl = try builder.finish(context: &run)
        let model = try NativeLogicSimulationCompiler().compile(rtl, context: &run)
        let evaluator = NativeLogicSimulationEvaluator(); var state = try evaluator.makeState(model, context: &run)
        let observed = try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: xz)]), state: &state, context: &run)
        #expect(try observed.output(at: 0).value.bit(at: 0) == .one)
    }

    @Test func twoStateConversionCannotAliasFourStateBranchSymbols() throws {
        var context = try LogicSimulationProbeFixtures.context()
        var guards = RTLGuardWorkspace()
        try guards.inputs.append(4, context: &context)
        try guards.inputs.append(5, context: &context)
        try guards.symbols.append(.init(expression: -2, bit: 2, inputs: 0..<2), context: &context)
        let converted = try guards.convertedToTwoState(6, base: 6, context: &context)
        #expect(converted != 6)
        #expect(try guards.convertedToTwoState(6, base: 6, context: &context) == converted)
        #expect(try guards.convertedToTwoState(converted, base: 6, context: &context) == converted)
        for source in 0..<4 {
            #expect(try guards.convertedToTwoState(source, base: 6, context: &context) == (source == 1 ? 1 : 0))
        }
        try guards.release(context: &context)
    }
}
