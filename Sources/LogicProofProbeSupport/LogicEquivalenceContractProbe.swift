import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicProof
import LogicSimulation

public enum LogicEquivalenceContractProbe {
    public static func id(_ raw: UInt64) throws(LogicKernelError) -> DesignEntityID {
        do { return try .init(rawValue: raw) } catch { throw .invalidInput("Invalid equivalence fixture identity") }
    }
    public static func correspondence(_ count: Int) throws(LogicKernelError) -> [LogicBitCorrespondence] {
        var result: [LogicBitCorrespondence] = []; result.reserveCapacity(count)
        for index in 0..<count { result.append(try .init(reference: index, candidate: index)) }
        return result
    }
    public static func problem(_ reference: LogicBinaryDesign, _ candidate: LogicBinaryDesign, inputs: Int, outputs: Int = 1,
                               context: inout LogicKernelContext) throws(LogicKernelError) -> LogicEquivalenceProblem {
        try .init(reference: reference, candidate: candidate, inputs: correspondence(inputs), outputs: correspondence(outputs),
            states: correspondence(reference.stateCount), context: &context)
    }
    public static func bit(_ operation: BitOperation = .and, inverted: Bool = false, invertedSecond: Bool = false, context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        let count = operation.operandCount
        var builder = try BitLogicBuilder(capacity: .init(nodes: count + 3, operands: count + 2,
            ports: count + 1, portBits: count + 1, states: 0), context: &context)
        var inputs: [BitNodeIndex] = []
        for index in 0..<count { inputs.append(try builder.addNode(id: id(UInt64(10 + index)), operation: .input, context: &context)) }
        var operands = inputs
        if invertedSecond {
            guard count >= 2 else { throw .invalidInput("Asymmetric fixture requires two operands") }
            operands[1] = try builder.addNode(id: id(19), operation: .invert, inputs: [inputs[1]], context: &context)
        }
        var output = try builder.addNode(id: id(20), operation: operation, inputs: operands, context: &context)
        if inverted { output = try builder.addNode(id: id(21), operation: .invert, inputs: [output], context: &context) }
        for index in inputs.indices { try builder.addPort(id: id(UInt64(30 + index)), direction: .input, bits: [inputs[index]], context: &context) }
        try builder.addPort(id: id(40), direction: .output, bits: [output], context: &context)
        return try builder.finish(context: &context)
    }
    public static func state(latch: Bool = false, loweredEnable: Bool = false, synchronousReset: Bool = false,
                             invertedReset: Bool = false, initial: Bool? = nil, bypassLatch: Bool = false,
                             risingEdge: Bool = true,
                             context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        var builder = try BitLogicBuilder(capacity: .init(nodes: 9, operands: 9, ports: 5, portBits: 5, states: 1), context: &context)
        var inputs: [BitNodeIndex] = []
        for index in 0..<4 { inputs.append(try builder.addNode(id: id(UInt64(10 + index)), operation: .input, context: &context)) }
        let q = try builder.addNode(id: id(20), operation: .state(.init(0)), context: &context)
        var next = inputs[0]
        if loweredEnable && !latch { next = try builder.addNode(id: id(21), operation: .select, inputs: [inputs[2], inputs[0], q], context: &context) }
        let reset = BitReset(signal: inputs[3], activeHigh: invertedReset, value: false, kind: synchronousReset ? .synchronous : .asynchronous)
        let control: BitStateControl = latch ? .latch(gate: inputs[1], activeHigh: true, reset: reset)
            : .flipFlop(clock: inputs[1], edge: risingEdge ? .rising : .falling, enable: loweredEnable ? nil : inputs[2], reset: reset)
        _ = try builder.addState(.init(id: id(50), next: next, control: control, initialValue: initial), context: &context)
        var output = q
        if bypassLatch {
            output = try builder.addNode(id: id(22), operation: .select, inputs: [inputs[1], inputs[0], q], context: &context)
            let zero = try builder.addNode(id: id(23), operation: .constant(false), context: &context)
            output = try builder.addNode(id: id(24), operation: .select, inputs: [inputs[3], output, zero], context: &context)
        }
        for index in inputs.indices { try builder.addPort(id: id(UInt64(30 + index)), direction: .input, bits: [inputs[index]], context: &context) }
        try builder.addPort(id: id(40), direction: .output, bits: [output], context: &context)
        return try builder.finish(context: &context)
    }
    public static func holdingState(initial: Bool, clearsOnEdge: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        var builder = try BitLogicBuilder(capacity: .init(nodes: 3, operands: 0, ports: 2, portBits: 2, states: 1), context: &context)
        let clock = try builder.addNode(id: id(10), operation: .input, context: &context)
        let q = try builder.addNode(id: id(11), operation: .state(.init(0)), context: &context)
        let zero = try builder.addNode(id: id(12), operation: .constant(false), context: &context)
        _ = try builder.addState(.init(id: id(50), next: clearsOnEdge ? zero : q, control: .flipFlop(clock: clock, edge: .rising, enable: nil, reset: nil), initialValue: initial), context: &context)
        try builder.addPort(id: id(30), direction: .input, bits: [clock], context: &context)
        try builder.addPort(id: id(40), direction: .output, bits: [q], context: &context)
        return try builder.finish(context: &context)
    }
    public static func mapped(nand: Bool, asymmetric: Bool = false, swapInputs: Bool = false, context: inout LogicKernelContext) throws(LogicKernelError) -> MappedGateDesign {
        var function = try LogicBooleanFunctionBuilder(inputCount: 3, nodeCapacity: 5, context: &context)
        let a = try function.append(.input(1), context: &context); var b = try function.append(.input(2), context: &context)
        if asymmetric { b = try function.append(.invert(b), context: &context) }
        var y = try function.append(.and(a,b), context: &context)
        if nand { y = try function.append(.invert(y), context: &context) }
        let output = try function.finish(output: y, context: &context)
        var cell = try LogicTechnologyCellBuilder(id: id(100), name: nand ? "NAND" : "AND", pinCapacity: 3, context: &context)
        _ = try cell.append(.init(id: id(101), name: "Y", direction: .output, function: output), context: &context)
        _ = try cell.append(.init(id: id(102), name: "A", direction: .input), context: &context)
        _ = try cell.append(.init(id: id(103), name: "B", direction: .input), context: &context)
        var library = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 3, context: &context)
        _ = try library.append(cell.finish(area: 1, state: nil, context: &context), context: &context)
        let source: ArtifactID
        do { source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: asymmetric ? "ef" : nand ? "ab" : "cd", count: 32)), byteCount: 10) }
        catch { throw .invalidInput("Invalid fixture library identity") }
        let published = try library.finish(source: source, context: &context)
        var graph = try MappedGateBuilder(library: published, capacity: .init(nets: 3, instances: 1, pinConnections: 3, ports: 3, portBits: 3), context: &context)
        _ = try graph.addNet(.init(id: id(200), driver: .input), context: &context)
        _ = try graph.addNet(.init(id: id(201), driver: .input), context: &context)
        _ = try graph.addNet(.init(id: id(202), driver: .instanceOutput(.init(0), .init(0))), context: &context)
        _ = try graph.addInstance(id: id(210), cell: .init(0), pinNets: [.init(2), .init(swapInputs ? 1 : 0), .init(swapInputs ? 0 : 1)], context: &context)
        for index in 0..<3 { try graph.addPort(id: id(UInt64(220 + index)), direction: index < 2 ? .input : .output, nets: [.init(index)], context: &context) }
        return try graph.finish(context: &context)
    }
    public static func mappedState(latch: Bool = false, initial: Bool? = nil, context: inout LogicKernelContext) throws(LogicKernelError) -> MappedGateDesign {
        var outputBuilder = try LogicBooleanFunctionBuilder(inputCount: 6, nodeCapacity: 1, context: &context)
        let q = try outputBuilder.append(.input(5), context: &context)
        let output = try outputBuilder.finish(output: q, context: &context)
        var nextBuilder = try LogicBooleanFunctionBuilder(inputCount: 6, nodeCapacity: 7, context: &context)
        let d = try nextBuilder.append(.input(1), context: &context)
        var next = d
        if !latch {
            let e = try nextBuilder.append(.input(3), context: &context)
            let old = try nextBuilder.append(.input(5), context: &context)
            let low = try nextBuilder.append(.invert(e), context: &context)
            let take = try nextBuilder.append(.and(e,d), context: &context)
            let hold = try nextBuilder.append(.and(low,old), context: &context)
            next = try nextBuilder.append(.or(take,hold), context: &context)
        }
        let data = try nextBuilder.finish(output: next, context: &context)
        var cell = try LogicTechnologyCellBuilder(id: id(100), name: latch ? "LAT" : "FFE", pinCapacity: 5, context: &context)
        _ = try cell.append(.init(id: id(101), name: "Q", direction: .output, function: output), context: &context)
        for (offset, name) in ["D","C","E","RN"].enumerated() {
            _ = try cell.append(.init(id: id(UInt64(102 + offset)), name: name, direction: .input), context: &context)
        }
        let definition = LogicCellStateDefinition(control: latch ? .latch(gate: .init(2), activeHigh: true) : .flipFlop(clock: .init(2), risingEdge: true),
            nextState: data, asynchronousReset: .init(pin: .init(4), activeHigh: false, value: false))
        let published = try cell.finish(area: 1, state: definition, context: &context)
        var libraryBuilder = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: 5, context: &context)
        _ = try libraryBuilder.append(published, context: &context)
        let source: ArtifactID
        do { source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: latch ? "12" : "34", count: 32)), byteCount: 10) }
        catch { throw .invalidInput("Invalid sequential fixture library identity") }
        let library = try libraryBuilder.finish(source: source, context: &context)
        var graph = try MappedGateBuilder(library: library, capacity: .init(nets: 5, instances: 1, pinConnections: 5, ports: 5, portBits: 5), context: &context)
        for index in 0..<4 { _ = try graph.addNet(.init(id: id(UInt64(200 + index)), driver: .input), context: &context) }
        _ = try graph.addNet(.init(id: id(204), driver: .instanceOutput(.init(0), .init(0))), context: &context)
        _ = try graph.addInstance(id: id(210), cell: .init(0), pinNets: [.init(4), .init(0), .init(1), .init(2), .init(3)], stateID: id(211), initialValue: initial, context: &context)
        for index in 0..<5 { try graph.addPort(id: id(UInt64(220 + index)), direction: index < 4 ? .input : .output, nets: [.init(index)], context: &context) }
        return try graph.finish(context: &context)
    }
    public static func exercise() throws(LogicKernelError) {
        var run = try LogicProofContractProbe.context()
        let and = try bit(context: &run); let nand = try mapped(nand: true, context: &run)
        let actualAND = try mapped(nand: false, context: &run)
        let checker: any LogicEquivalenceChecking = NativeLogicEquivalenceChecker()
        let equal = try problem(.bit(and), .mapped(actualAND), inputs: 2, context: &run)
        guard case .equivalent(let checked) = try checker.check(equal, context: &run) else { throw .invalidModel("Actual AND equivalence was not proved") }
        try checked.requireBinding(to: equal)
        let wrong = try problem(.bit(and), .mapped(nand), inputs: 2, context: &run)
        guard case .different(let witness) = try checker.check(wrong, context: &run), witness.hasConcreteEventDifference else { throw .invalidModel("Wrong actual NAND mapping escaped replay") }
        try witness.requireBinding(to: wrong)
        guard witness.withEventControls({ _, _ in true }) == nil, witness.previousControl == nil else {
            throw .invalidModel("Combinational witness invented physical FF history")
        }
        let ff = try state(context: &run); let mux = try state(loweredEnable: true, context: &run)
        let sequential = try problem(.bit(ff), .bit(mux), inputs: 4, context: &run)
        guard case .equivalent(let proof) = try checker.check(sequential, context: &run) else { throw .invalidModel("State-preserving enable lowering was not proved") }
        try proof.requireBinding(to: sequential)
        for latch in [false, true] {
            let original = try state(latch: latch, context: &run)
            let actual = try mappedState(latch: latch, context: &run)
            let problem = try Self.problem(.bit(original), .mapped(actual), inputs: 4, context: &run)
            guard case .equivalent(let proof) = try checker.check(problem, context: &run) else { throw .invalidModel("Actual sequential cell was not proved equivalent") }
            try proof.requireBinding(to: problem)
        }
    }
}
