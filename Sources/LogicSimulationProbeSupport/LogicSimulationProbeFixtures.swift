import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicSimulation

public enum LogicSimulationProbeFixtures {
    public static func id(_ raw: UInt64) throws(LogicKernelError) -> DesignEntityID {
        do { return try .init(rawValue: raw) } catch { throw .invalidInput("Invalid probe identity") }
    }
    public static func context(limit: UInt64 = 10_000_000, control: any LogicRunControlling = Control()) throws(LogicKernelError) -> LogicKernelContext {
        .init(limits: try .init(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, limit) })), control: control)
    }
    public struct Control: LogicRunControlling {
        public init() {}
        public func checkpoint() throws(LogicKernelError) {}
    }
    public static func vector(_ bit: LogicBit, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        try .init(repeating: bit, width: .init(1), context: &context)
    }
    private static func function(slots: Int, input: Int, nand: Bool = false, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBooleanFunction {
        var b = try LogicBooleanFunctionBuilder(inputCount: slots, nodeCapacity: 4, context: &context)
        var out = try b.append(.input(input), context: &context)
        if nand {
            let second = try b.append(.input(2), context: &context)
            out = try b.append(.and(out, second), context: &context)
            out = try b.append(.invert(out), context: &context)
        }
        return try b.finish(output: out, context: &context)
    }
    public static func design(sequential: Bool = false, latch: Bool = false, context: inout LogicKernelContext) throws(LogicKernelError) -> MappedGateDesign {
        let pinCount = sequential ? 4 : 3
        var cell = try LogicTechnologyCellBuilder(id: id(100), name: sequential ? "SEQ" : "NAND", pinCapacity: pinCount, context: &context)
        let output = try function(slots: pinCount + (sequential ? 1 : 0), input: sequential ? pinCount : 1, nand: !sequential, context: &context)
        _ = try cell.append(.init(id: id(101), name: "Y", direction: .output, function: output), context: &context)
        _ = try cell.append(.init(id: id(102), name: "D", direction: .input), context: &context)
        _ = try cell.append(.init(id: id(103), name: "C", direction: .input), context: &context)
        if sequential { _ = try cell.append(.init(id: id(104), name: "RN", direction: .input), context: &context) }
        let definition: LogicCellStateDefinition?
        if sequential {
            let data = try function(slots: 5, input: 1, context: &context)
            definition = .init(control: latch ? .latch(gate: .init(2), activeHigh: true) : .flipFlop(clock: .init(2), risingEdge: true),
                nextState: data, asynchronousReset: .init(pin: .init(3), activeHigh: false, value: false))
        } else { definition = nil }
        let published = try cell.finish(area: 1, state: definition, context: &context)
        var lib = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: pinCount, context: &context)
        _ = try lib.append(published, context: &context)
        let source: ArtifactID
        do { source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "ab", count: 32)), byteCount: 1000) }
        catch { throw .invalidInput("Probe source identity is invalid") }
        let library = try lib.finish(source: source, context: &context)
        let count = sequential && !latch ? 2 : 1
        let inputCount = sequential ? 3 : 2
        var graph = try MappedGateBuilder(library: library, capacity: .init(nets: inputCount + count,
            instances: count, pinConnections: pinCount * count, ports: inputCount + count, portBits: inputCount + count), context: &context)
        for index in 0..<inputCount { _ = try graph.addNet(.init(id: id(UInt64(200 + index)), driver: .input), context: &context) }
        for index in 0..<count {
            _ = try graph.addNet(.init(id: id(UInt64(210 + index)), driver: .instanceOutput(.init(index), .init(0))), context: &context)
        }
        for index in 0..<count {
            var pins: [MappedNetIndex] = [.init(inputCount + index), .init(index == 0 ? 0 : inputCount), .init(1)]
            if sequential { pins.append(.init(2)) }
            _ = try graph.addInstance(id: id(UInt64(220 + index)), cell: .init(0), pinNets: pins,
                stateID: sequential ? id(UInt64(230 + index)) : nil, context: &context)
        }
        for index in 0..<(inputCount + count) {
            try graph.addPort(id: id(UInt64(240 + index)), direction: index < inputCount ? .input : .output, nets: [.init(index)], context: &context)
        }
        return try graph.finish(context: &context)
    }
    public static func event(_ bits: [LogicBit], time: UInt64 = 0, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicInputEvent {
        var updates: [LogicInputEvent.Update] = []
        for index in bits.indices { updates.append(.init(portIndex: index, value: try vector(bits[index], context: &context))) }
        return .init(time: time, updates: updates)
    }
    public static func exercise() throws(LogicKernelError) {
        var run = try context()
        let compiler: any LogicSimulationCompiling = NativeLogicSimulationCompiler()
        let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
        let graph = try design(context: &run)
        let model = try compiler.compile(graph, library: graph.library, context: &run)
        var state = try evaluator.makeState(model, context: &run)
        for a in [LogicBit.zero, .one, .unknown, .highImpedance] {
            for b in [LogicBit.zero, .one, .unknown, .highImpedance] {
                let output = try evaluator.evaluate(model, event: event([a, b], context: &run), state: &state, context: &run)
                let expected: LogicBit = a == .zero || b == .zero ? .one : a == .one && b == .one ? .zero : .unknown
                guard try output.output(at: 0).value.bit(at: 0) == expected else { throw .invalidModel("Actual NAND truth contract failed") }
            }
        }
        for latch in [false, true] {
            let graph = try design(sequential: true, latch: latch, context: &run)
            let model = try compiler.compile(graph, library: graph.library, context: &run)
            var state = try evaluator.makeState(model, context: &run)
            _ = try evaluator.evaluate(model, event: event([.zero, .zero, .zero], context: &run), state: &state, context: &run)
            let released = try evaluator.evaluate(model, event: event([.one, .zero, .one], context: &run), state: &state, context: &run)
            guard try released.output(at: 0).value.bit(at: 0) == .zero else { throw .invalidModel("Reset release changed closed state") }
            let first = try evaluator.evaluate(model, event: event([.one, .one, .one], context: &run), state: &state, context: &run)
            guard try first.output(at: 0).value.bit(at: 0) == .one else { throw .invalidModel("State did not capture data") }
            if !latch {
                guard try first.output(at: 1).value.bit(at: 0) == .zero else { throw .invalidModel("FFs did not sample simultaneously") }
            }
            let asserted = try evaluator.evaluate(model, event: event([.one, .one, .zero], context: &run), state: &state, context: &run)
            guard try asserted.output(at: 0).value.bit(at: 0) == .zero else { throw .invalidModel("Asynchronous reset did not assert") }
            if !latch {
                let release = try evaluator.evaluate(model, event: event([.one, .one, .one], context: &run), state: &state, context: &run)
                guard try release.output(at: 0).value.bit(at: 0) == .zero else { throw .invalidModel("Reset release created a clock edge") }
            }
        }
    }
}
