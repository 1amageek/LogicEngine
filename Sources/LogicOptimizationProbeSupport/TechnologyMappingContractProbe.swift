import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicSynthesis
import LogicProof
import LogicSimulation
import LogicProofProbeSupport
import LogicLowering
import SystemVerilogFrontend
import LogicWordLoweringProbeSupport

public enum TechnologyMappingContractProbe {
    private typealias F = LogicEquivalenceContractProbe
    public enum Gate { case inverter, and, nand, nor, xor, asymmetric, mux, dual }
    public static func policy(inputs: Int = 3, cuts: Int = 8) throws(LogicKernelError) -> LogicMappingPolicy {
        try .init(maximumCutInputs: inputs, maximumCellInputs: 6, maximumCutsPerNode: cuts, firstEntityID: F.id(10_000))
    }
    public static func cell(_ gate: Gate, id: UInt64, area: Double, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicTechnologyCell {
        let count = gate == .inverter ? 2 : gate == .mux || gate == .dual ? 4 : 3
        func function(inverted: Bool = false) throws(LogicKernelError) -> LogicBooleanFunction {
            var b = try LogicBooleanFunctionBuilder(inputCount: count, nodeCapacity: 12, context: &context)
            let a = try b.append(.input(1), context: &context)
            let y: LogicBooleanNodeIndex
            if gate == .inverter { y = try b.append(.invert(a), context: &context) }
            else {
                let second = try b.append(.input(2), context: &context)
                switch gate {
                case .nand: let both = try b.append(.and(a,second), context: &context); y = try b.append(.invert(both), context: &context)
                case .nor: let either = try b.append(.or(a,second), context: &context); y = try b.append(.invert(either), context: &context)
                case .xor: y = try b.append(.xor(a,second), context: &context)
                case .asymmetric: let na = try b.append(.invert(a), context: &context); y = try b.append(.and(na,second), context: &context)
                case .mux:
                    let c = try b.append(.input(3), context: &context)
                    let nc = try b.append(.invert(c), context: &context)
                    let take = try b.append(.and(c,a), context: &context); let hold = try b.append(.and(nc,second), context: &context)
                    y = try b.append(.or(take,hold), context: &context)
                default: y = try b.append(.and(a,second), context: &context)
                }
            }
            let output = inverted ? try b.append(.invert(y), context: &context) : y
            return try b.finish(output: output, context: &context)
        }
        let output = try function()
        var builder = try LogicTechnologyCellBuilder(id: F.id(id), name: "misleading_cell_\(id)", pinCapacity: count, context: &context)
        _ = try builder.append(.init(id: F.id(id+1), name: "Y", direction: .output, function: output), context: &context)
        _ = try builder.append(.init(id: F.id(id+2), name: "B", direction: .input), context: &context)
        if count > 2 { _ = try builder.append(.init(id: F.id(id+3), name: "A", direction: .input), context: &context) }
        if gate == .mux { _ = try builder.append(.init(id: F.id(id+4), name: "S", direction: .input), context: &context) }
        if gate == .dual { _ = try builder.append(.init(id: F.id(id+4), name: "YN", direction: .output, function: function(inverted: true)), context: &context) }
        return try builder.finish(area: area, context: &context)
    }
    public static func sequentialCell(id: UInt64 = 1000, latch: Bool = false, high: Bool = true, asynchronous: Bool = false,
                                      resetHigh: Bool = false, resetValue: Bool = false,
                                      enabled: Bool = false, invertedOutput: Bool = false,
                                      context: inout LogicKernelContext) throws(LogicKernelError) -> LogicTechnologyCell {
        var output = try LogicBooleanFunctionBuilder(inputCount: 6, nodeCapacity: 2, context: &context)
        let q = try output.append(.input(5), context: &context)
        let y = invertedOutput ? try output.append(.invert(q), context: &context) : q
        let outputFunction = try output.finish(output: y, context: &context)
        var next = try LogicBooleanFunctionBuilder(inputCount: 6, nodeCapacity: 8, context: &context)
        var d = try next.append(.input(1), context: &context)
        if enabled {
            let enable = try next.append(.input(3), context: &context); let ne = try next.append(.invert(enable), context: &context)
            let state = try next.append(.input(5), context: &context)
            let take = try next.append(.and(enable,d), context: &context); let hold = try next.append(.and(ne,state), context: &context)
            d = try next.append(.or(take,hold), context: &context)
        }
        let nextFunction = try next.finish(output: d, context: &context)
        var cell = try LogicTechnologyCellBuilder(id: F.id(id), name: "actual_state_\(id)", pinCapacity: 5, context: &context)
        _ = try cell.append(.init(id: F.id(id+1), name: "QN", direction: .output, function: outputFunction), context: &context)
        for (index, name) in ["D", "C", "E", "R"].enumerated() {
            _ = try cell.append(.init(id: F.id(id+UInt64(2+index)), name: name, direction: .input), context: &context)
        }
        return try cell.finish(area: 3, state: .init(control: latch ? .latch(gate: .init(2), activeHigh: high) : .flipFlop(clock: .init(2), risingEdge: high),
            nextState: nextFunction, asynchronousReset: asynchronous ? .init(pin: .init(4), activeHigh: resetHigh, value: resetValue) : nil), context: &context)
    }
    public static func library(_ cells: [LogicTechnologyCell], context: inout LogicKernelContext) throws(LogicKernelError) -> LogicTechnologyLibrary {
        var pins = 0
        for cell in cells { pins += cell.pinCount }
        var builder = try LogicTechnologyLibraryBuilder(cellCapacity: cells.count, totalPinCapacity: pins, context: &context)
        for cell in cells { _ = try builder.append(cell, context: &context) }
        let source: ArtifactID
        do { source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "78", count: 32)), byteCount: 1) }
        catch { throw .invalidInput("Invalid mapping fixture identity") }
        return try builder.finish(source: source, context: &context)
    }
    public static func verify(_ source: borrowing BitLogicDesign, library: borrowing LogicTechnologyLibrary,
                              context: inout LogicKernelContext) throws(LogicKernelError) -> LogicMappingCandidate {
        let mapper: any LogicTechnologyMapping = NativeLogicTechnologyMapper()
        let candidate = try mapper.map(source, library: library, policy: policy(), context: &context)
        let counts = source.withTables { _, _, ports, _, _, _ in
            var inputs = 0; var outputs = 0
            for i in ports.indices { if ports[i].direction == .input { inputs += ports[i].bits.count } else { outputs += ports[i].bits.count } }
            return (inputs,outputs)
        }
        let problem = try F.problem(.bit(copy source), .mapped(candidate.design), inputs: counts.0, outputs: counts.1, context: &context)
        let checker: any LogicEquivalenceChecking = NativeLogicEquivalenceChecker()
        guard case .equivalent(let proof) = try checker.check(problem, context: &context) else { throw .invalidModel("Actual technology mapping did not prove equivalent") }
        try proof.requireBinding(to: problem)
        let rechecker: any LogicEquivalenceProofRechecking = NativeLogicEquivalenceChecker()
        let rechecked = try rechecker.recheck(problem, certificate: proof.proof.certificate, context: &context)
        try rechecked.requireBinding(to: problem)
        let measuring: any LogicMappedDesignMeasuring = NativeLogicTechnologyMapper()
        let actual = try measuring.measure(candidate.design, context: &context)
        guard actual.instanceCount == candidate.statistics.instanceCount,
              actual.area == candidate.statistics.area, actual.combinationalDepth == candidate.statistics.combinationalDepth else {
            throw .invalidModel("Recomputed actual metrics differ from mapping output")
        }
        if counts.0 + source.stateCount <= 6 {
            let evaluator: any LogicBinaryEvaluating = NativeLogicBinaryEvaluator()
            for assignment in 0..<(1 << (counts.0 + source.stateCount)) {
                var inputs = [Bool](repeating: false, count: counts.0)
                var states = [Bool](repeating: false, count: source.stateCount)
                for i in inputs.indices { inputs[i] = assignment & (1 << i) != 0 }
                for i in states.indices { states[i] = assignment & (1 << (i + inputs.count)) != 0 }
                let reference = try evaluator.evaluate(.bit(copy source), inputs: inputs.span, currentState: states.span, context: &context)
                let mapped = try evaluator.evaluate(.mapped(candidate.design), inputs: inputs.span, currentState: states.span, context: &context)
                let equal = reference.withTables { oldOutputs, oldActions in
                    mapped.withTables { newOutputs, newActions in
                        guard oldOutputs.count == newOutputs.count, oldActions.count == newActions.count else { return false }
                        for i in oldOutputs.indices where oldOutputs[i] != newOutputs[i] { return false }
                        for i in oldActions.indices where oldActions[i] != newActions[i] { return false }
                        return true
                    }
                }
                guard equal else { throw .invalidModel("Exhaustive actual-function relation differs") }
            }
        }
        var area: Double = 0
        try candidate.design.withTables { _, instances, _, _, _, _ throws(LogicKernelError) in
            for i in instances.indices { area += try library.cell(at: instances[i].cell).area }
        }
        guard area == candidate.statistics.area, candidate.statistics.instanceCount == candidate.design.instanceCount else {
            throw .invalidModel("Metrics do not count actual instances")
        }
        return candidate
    }
    public static func combinational() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        for gate in [Gate.nand, .nor] {
            let library = try library([cell(gate, id: 100, area: 1, context: &context)], context: &context)
            for op in [BitOperation.and, .or, .xor, .invert, .buffer, .select, .constant(false), .constant(true)] {
                let source = try F.bit(op, context: &context)
                _ = try verify(source, library: library, context: &context)
            }
        }
    }
    public static func permutationsAndMultiOutput() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let library = try library([cell(.asymmetric, id: 200, area: 0.5, context: &context), cell(.dual, id: 100, area: 1, context: &context), cell(.inverter, id: 300, area: 0.1, context: &context)], context: &context)
        let source = try F.bit(invertedSecond: true, context: &context)
        let candidate = try verify(source, library: library, context: &context)
        let used = try candidate.design.withTables { _, instances, _, _, _, _ throws(LogicKernelError) in
            var asymmetric = false
            for i in instances.indices { if try library.cell(at: instances[i].cell).id.rawValue == 200 { asymmetric = true } }
            return asymmetric
        }
        guard used else { throw .invalidModel("Pin permutation fixture did not select the actual asymmetric function") }
        let dualLibrary = try Self.library([cell(.dual, id: 100, area: 1, context: &context)], context: &context)
        let and = try F.bit(context: &context)
        let dual = try verify(and, library: dualLibrary, context: &context)
        guard dual.design.instanceCount == 1, dual.design.netCount == 4 else { throw .invalidModel("Multi-output cell lost a physical output") }
    }
    public static func sequential() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        for latch in [false,true] {
            for sync in (latch ? [false] : [false,true]) {
                let library = try Self.library([cell(.nand, id: 100, area: 1, context: &context),
                    sequentialCell(latch: latch, asynchronous: !sync, enabled: !latch, invertedOutput: true, context: &context)], context: &context)
                let source = try F.state(latch: latch, synchronousReset: sync, context: &context)
                let mapped = try verify(source, library: library, context: &context)
                guard mapped.design.stateCount == 1 else { throw .invalidModel("State bit was removed") }
            }
        }
        let fallingLibrary = try Self.library([cell(.nand,id:100,area:1,context:&context), sequentialCell(high:false,asynchronous:true,context:&context)],context:&context)
        _ = try verify(F.state(risingEdge:false,context:&context), library:fallingLibrary,context:&context)
    }
    public static func sourceIntegration() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let text = "module p(input [7:0] a,b,output [7:0] y);assign y=(a&b)|(a&b);endmodule"
        let bytes = Array(text.utf8); let identity: ArtifactID
        do { identity = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: "a0e065c299632e64d177341f7a917b666f7a4b83abf30afa76e52f85b7f25cc6"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidInput("Invalid source mapping fixture") }
        let document = try LogicSourceDocument(logicalName: "p.sv", artifactID: identity, bytes: bytes, context: &context)
        let bundle = try LogicSourceBundle(documents: [document], context: &context)
        let frontend: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
        let rtl = try frontend.elaborate(bundle, options: SourceLoweringContractProbe.options(["p.sv"]), context: &context)
        let word = try NativeLogicWordLowering().lower(rtl, context: &context)
        let bit = try NativeLogicBitLowering().lower(word, context: &context)
        let library = try Self.library([cell(.nand,id:100,area:1,context:&context)],context:&context)
        let optimized = try NativeLogicOptimizer().optimize(bit, context: &context)
        let mapper: any LogicTechnologyMapping = NativeLogicTechnologyMapper()
        let mapped = try mapper.map(optimized.design, library: library, policy: policy(), context: &context)
        let problem = try F.problem(.bit(bit), .mapped(mapped.design), inputs: 16, outputs: 8, context: &context)
        guard case .equivalent(let proof) = try NativeLogicEquivalenceChecker().check(problem, context: &context) else {
            throw .invalidModel("Source-to-optimized-to-mapped composition did not prove equivalent")
        }
        try proof.requireBinding(to: problem)
        guard mapped.design.instanceCount >= 8 else { throw .invalidModel("Eight-bit AND collapsed to one one-bit cell") }
    }
    public static func exercise() throws(LogicKernelError) {
        try combinational(); try permutationsAndMultiOutput(); try sequential(); try sourceIntegration()
        try stableSelectionAndTopology(); try rejectWrongStateControls(); try tamperedPinsFailIndependentProof(); try sixInputCutAndAbsorbedNodes(); try sourceStateIntegration(); try startupAndPhysicalTies()
    }
}
