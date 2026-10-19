import Testing
import LogicIR
import LogicKernelCore
import LogicSimulation
import LogicSimulationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct CellEventsTests {
    private typealias F = LogicSimulationProbeFixtures
    @Test func actualTruthResetReleaseAndSimultaneousFFSampling() throws { try F.exercise() }
    @Test func initialUnknownAndXClockEdgesAndLatchHoldAreExplicit() throws {
        for latch in [false, true] {
            var run = try F.context()
            let graph = try F.design(sequential: true, latch: latch, context: &run)
            let model = try NativeLogicSimulationCompiler().compile(graph, library: graph.library, context: &run)
            let evaluator = NativeLogicSimulationEvaluator()
            var state = try evaluator.makeState(model, context: &run)
            let initial = try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &run)
            #expect(try initial.output(at: 0).value.bit(at: 0) == .unknown)
            _ = try evaluator.evaluate(model, event: F.event([.zero, .zero, .zero], context: &run), state: &state, context: &run)
            _ = try evaluator.evaluate(model, event: F.event([.one, .zero, .one], context: &run), state: &state, context: &run)
            let unknownClock = try evaluator.evaluate(model, event: F.event([.one, .unknown, .one], context: &run), state: &state, context: &run)
            #expect(try unknownClock.output(at: 0).value.bit(at: 0) == (latch ? .unknown : .one))
            _ = try evaluator.evaluate(model, event: F.event([.one, .one, .one], context: &run), state: &state, context: &run)
            let changed = try evaluator.evaluate(model, event: F.event([.zero, .one, .one], context: &run), state: &state, context: &run)
            #expect(try changed.output(at: 0).value.bit(at: 0) == (latch ? .zero : .one))
        }
    }
    @Test func modelBindingInvalidEventsAndTimeRegressionFail() throws {
        var run = try F.context()
        let graph = try F.design(context: &run)
        let compiler = NativeLogicSimulationCompiler(); let evaluator = NativeLogicSimulationEvaluator()
        let model = try compiler.compile(graph, library: graph.library, context: &run)
        let other = try compiler.compile(graph, library: graph.library, context: &run)
        var state = try evaluator.makeState(model, context: &run)
        #expect(throws: LogicKernelError.self) { try evaluator.evaluate(other, event: .init(time: 0, updates: []), state: &state, context: &run) }
        let otherGraph = try F.design(sequential: true, context: &run)
        #expect(throws: LogicKernelError.self) { try compiler.compile(graph, library: otherGraph.library, context: &run) }
        let wide = try LogicFourStateVector(repeating: .one, width: .init(2), context: &run)
        #expect(throws: LogicKernelError.self) { try evaluator.evaluate(model, event: .init(time: 0, updates: [.init(portIndex: 0, value: wide)]), state: &state, context: &run) }
        let v = try F.vector(.one, context: &run)
        for updates in [[LogicInputEvent.Update(portIndex: -1, value: v)], [.init(portIndex: 2, value: v)],
                        [.init(portIndex: 0, value: v), .init(portIndex: 0, value: v)]] {
            #expect(throws: LogicKernelError.self) { try evaluator.evaluate(model, event: .init(time: 0, updates: updates), state: &state, context: &run) }
        }
        _ = try evaluator.evaluate(model, event: F.event([.one, .one], time: 3, context: &run), state: &state, context: &run)
        #expect(throws: LogicKernelError.self) { try evaluator.evaluate(model, event: .init(time: 2, updates: []), state: &state, context: &run) }
    }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    @Test func cancellationDoesNotPublishACompiledModel() throws {
        var run = try F.context()
        let graph = try F.design(context: &run)
        var cancelled = try F.context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try NativeLogicSimulationCompiler().compile(graph, library: graph.library, context: &cancelled) }
    }
    @Test func previouslyBuiltDesignMustFitTheRunModelLimits() throws {
        var run = try F.context()
        let graph = try F.design(context: &run)
        let model = try NativeLogicSimulationCompiler().compile(graph, library: graph.library, context: &run)
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        limits[.nodes] = 1
        var bounded = LogicKernelContext(limits: try .init(maximums: limits), control: F.Control())
        #expect(throws: LogicKernelError.self) { try NativeLogicSimulationCompiler().compile(graph, library: graph.library, context: &bounded) }
        #expect(throws: LogicKernelError.self) { try NativeLogicSimulationEvaluator().makeState(model, context: &bounded) }
    }
    @Test func eventFailureInvalidatesStateUntilExplicitRestart() throws {
        var run = try F.context()
        let graph = try F.design(context: &run)
        let model = try NativeLogicSimulationCompiler().compile(graph, library: graph.library, context: &run)
        let evaluator = NativeLogicSimulationEvaluator()
        var state = try evaluator.makeState(model, context: &run)
        var exhausted = try F.context(limit: 1)
        #expect(throws: LogicKernelError.self) { try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &exhausted) }
        #expect(throws: LogicKernelError.self) { try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &run) }
        var restarted = try evaluator.makeState(model, context: &run)
        #expect(try evaluator.evaluate(model, event: F.event([.zero, .one], context: &run), state: &restarted, context: &run).output(at: 0).value.bit(at: 0) == .one)
    }
}
