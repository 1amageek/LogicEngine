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

public enum LogicOptimizationContractProbe {
    private typealias F = LogicEquivalenceContractProbe
    public static func fixture(seed: UInt64, reversedIDs: Bool = false, context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        var builder = try BitLogicBuilder(capacity: .init(nodes: 35, operands: 90, ports: 2, portBits: 6, states: 0), context: &context)
        var nodes: [BitNodeIndex] = []
        for index in 0..<3 { nodes.append(try builder.addNode(id: F.id(UInt64(reversedIDs ? 100 - index : index + 1)), operation: .input, context: &context)) }
        for value in [false, true] { nodes.append(try builder.addNode(id: F.id(UInt64(reversedIDs ? 100 - nodes.count : nodes.count + 1)), operation: .constant(value), context: &context)) }
        var random = seed
        for index in 5..<35 {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            let opcode = Int((random >> 32) % 7)
            let operation: BitOperation
            switch opcode { case 0: operation = .buffer; case 1: operation = .invert; case 2: operation = .and
            case 3: operation = .or; case 4: operation = .xor; default: operation = .select }
            var operands: [BitNodeIndex] = []
            for _ in 0..<operation.operandCount {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                operands.append(nodes[Int((random >> 32) % UInt64(nodes.count))])
            }
            nodes.append(try builder.addNode(id: F.id(UInt64(reversedIDs ? 100 - index : index + 1)), operation: operation, inputs: operands, context: &context))
        }
        try builder.addPort(id: F.id(200), direction: .input, bits: [nodes[0],nodes[1],nodes[2]], context: &context)
        try builder.addPort(id: F.id(201), direction: .output, bits: [nodes[32],nodes[33],nodes[34]], context: &context)
        return try builder.finish(context: &context)
    }
    public static func identities(context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        var builder = try BitLogicBuilder(capacity: .init(nodes: 22, operands: 40, ports: 2, portBits: 16, states: 0), context: &context)
        var nodes: [BitNodeIndex] = []
        let specifications: [(BitOperation, [Int])] = [
            (.input, []), (.input, []), (.constant(false), []), (.constant(true), []),
            (.buffer, [0]), (.invert, [0]), (.invert, [5]),
            (.and, [0,3]), (.and, [0,2]), (.and, [0,0]), (.and, [0,5]),
            (.or, [0,2]), (.or, [0,3]), (.or, [0,5]),
            (.xor, [0,0]), (.xor, [0,5]), (.xor, [0,3]),
            (.select, [0,3,2]), (.select, [0,2,3]),
            (.and, [0,1]), (.and, [1,0]), (.xor, [0,1])]
        for index in specifications.indices {
            var operands: [BitNodeIndex] = []
            for source in specifications[index].1 { operands.append(nodes[source]) }
            nodes.append(try builder.addNode(id: F.id(UInt64(index + 1)), operation: specifications[index].0, inputs: operands, context: &context))
        }
        try builder.addPort(id: F.id(200), direction: .input, bits: [nodes[0], nodes[1]], context: &context)
        var outputs: [BitNodeIndex] = []
        for index in 7...20 { outputs.append(nodes[index]) }
        try builder.addPort(id: F.id(201), direction: .output, bits: outputs, context: &context)
        return try builder.finish(context: &context)
    }
    public static func values(_ graph: borrowing BitLogicDesign, inputs: borrowing [Bool], states: borrowing [Bool] = []) -> [Bool] {
        graph.withTables { nodes, operands, ports, bits, _, order in
            var values = [Bool](repeating: false, count: nodes.count); var input = 0
            for p in ports.indices where ports[p].direction == .input {
                for bit in ports[p].bits { values[bits[bit].rawValue] = inputs[input]; input += 1 }
            }
            for position in order.indices {
                let index = order[position].rawValue; let node = nodes[index]
                let a = node.operands.isEmpty ? false : values[operands[node.operands.lowerBound].rawValue]
                let b = node.operands.count < 2 ? false : values[operands[node.operands.lowerBound + 1].rawValue]
                let c = node.operands.count < 3 ? false : values[operands[node.operands.lowerBound + 2].rawValue]
                switch node.operation {
                case .input: break
                case .state(let s): values[index] = states[s.rawValue]
                case .constant(let v): values[index] = v
                case .buffer: values[index] = a
                case .invert: values[index] = !a
                case .and: values[index] = a && b
                case .or: values[index] = a || b
                case .xor: values[index] = a != b
                case .select: values[index] = a ? b : c
                }
            }
            return values
        }
    }
    public static func verify(_ graph: borrowing BitLogicDesign, inputs: Int, outputs: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicOptimizationCandidate {
        let sourceOwner = copy graph
        let optimizer: any LogicOptimizing = NativeLogicOptimizer()
        let candidate = try optimizer.optimize(graph, context: &context)
        let problem = try F.problem(.bit(sourceOwner), .bit(candidate.design), inputs: inputs, outputs: outputs, context: &context)
        let checker: any LogicEquivalenceChecking = NativeLogicEquivalenceChecker()
        guard case .equivalent(let checked) = try checker.check(problem, context: &context) else { throw .invalidModel("Optimization changed a binary relation") }
        try checked.requireBinding(to: problem)
        if inputs + graph.stateCount <= 8 {
            for assignment in 0..<(1 << (inputs + graph.stateCount)) {
                var input: [Bool] = []; var state: [Bool] = []
                for bit in 0..<inputs { input.append(assignment & (1 << bit) != 0) }
                for bit in 0..<graph.stateCount { state.append(assignment & (1 << (inputs + bit)) != 0) }
                let old = values(graph, inputs: input, states: state)
                let new = values(candidate.design, inputs: input, states: state)
                try candidate.withOrigins { origins throws(LogicKernelError) in
                    guard origins.count == graph.nodeCount else { throw .invalidModel("Incomplete origin correspondence") }
                    for index in origins.indices {
                        guard origins[index].source.rawValue == index else { throw .invalidModel("Unstable source correspondence") }
                        if let target = origins[index].destination, old[index] != new[target.rawValue] { throw .invalidModel("Origin correspondence changed its function") }
                    }
                }
            }
        }
        return candidate
    }
    public static func sourceIntegration(context: inout LogicKernelContext) throws(LogicKernelError) {
        let text = "module p(input [7:0] a,b,output [7:0] y);assign y=(a&b)|(a&b);endmodule"
        let bytes = Array(text.utf8)
        let artifact: ArtifactID
        do { artifact = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: "a0e065c299632e64d177341f7a917b666f7a4b83abf30afa76e52f85b7f25cc6"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidInput("Invalid source fixture digest") }
        let doc = try LogicSourceDocument(logicalName: "p.sv", artifactID: artifact, bytes: bytes, context: &context)
        let bundle = try LogicSourceBundle(documents: [doc], context: &context)
        let frontend: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
        let rtl = try frontend.elaborate(bundle, options: SourceLoweringContractProbe.options(["p.sv"]), context: &context)
        let compiler: any LogicSimulationCompiling = NativeLogicSimulationCompiler()
        let model = try compiler.compile(rtl, context: &context)
        let evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()
        var simulation = try evaluator.makeState(model, context: &context)
        let unknown = try evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &simulation, context: &context)
        for index in 0..<8 {
            guard try unknown.output(at: 0).value.bit(at: index) == .unknown else { throw .invalidModel("Uninitialized RTL was not unknown") }
        }
        let word = try NativeLogicWordLowering().lower(rtl, context: &context)
        let bit = try NativeLogicBitLowering().lower(word, context: &context)
        let candidate = try verify(bit, inputs: 16, outputs: 8, context: &context)
        let gates = candidate.design.withNodes { nodes in
            var result = 0; for index in nodes.indices { if case .and = nodes[index].operation { result += 1 } }; return result
        }
        guard gates == 8 else { throw .invalidModel("Eight-bit AND did not preserve eight bit gates") }
        for a in 0..<256 {
            let b = (a * 73 + 17) & 255
            let observed = try SourceLoweringContractProbe.observe(candidate.design, inputs: [UInt64(a),UInt64(b)])
            let av = try LogicFourStateVector(width: .init(8), valueWords: [UInt64(a)], unknownWords: [0])
            let bv = try LogicFourStateVector(width: .init(8), valueWords: [UInt64(b)], unknownWords: [0])
            let rtlObservation = try evaluator.evaluate(model, event: .init(time: UInt64(a + 1), updates: [.init(portIndex: 0, value: av), .init(portIndex: 1, value: bv)]), state: &simulation, context: &context)
            let fourState = try rtlObservation.output(at: 0).value
            for bit in 0..<8 {
                guard try fourState.bit(at: bit) == ((a & b) & (1 << bit) == 0 ? .zero : .one) else { throw .invalidModel("RTL simulation and optimized result differ") }
            }
            guard observed.outputs == [UInt64(a & b)] else { throw .invalidModel("Source-to-optimized result differs") }
        }
    }
    public static func sequentialSourceIntegration(context: inout LogicKernelContext) throws(LogicKernelError) {
        let texts = ["module p(input clk,rst_n,en,input [1:0] d,output logic [1:0] q);always_ff @(posedge clk or negedge rst_n)if(!rst_n)q<=0;else if(en)q<=d;endmodule", "module p(input gate,input [1:0] d,output logic [1:0] q);always_latch if(gate)q=d;endmodule"]
        let digests = ["3ab832f6eacef7a60c5d3215d05052908b3d048254cf5b1b1ccf49d204ab9f36", "c0e916bd3402ff70e26d9d3a5176179dd14c0a5f230b6062c9e95daf290b0a2c"]
        for index in texts.indices {
            let bytes = Array(texts[index].utf8)
            let artifact: ArtifactID
            do { artifact = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: digests[index]), byteCount: UInt64(bytes.count)) }
            catch { throw .invalidInput("Invalid sequential source identity") }
            let doc = try LogicSourceDocument(logicalName: "p.sv", artifactID: artifact, bytes: bytes, context: &context)
            let bundle = try LogicSourceBundle(documents: [doc], context: &context)
            let rtl = try NativeSystemVerilogElaborator().elaborate(bundle, options: SourceLoweringContractProbe.options(["p.sv"]), context: &context)
            let word = try NativeLogicWordLowering().lower(rtl, context: &context)
            let bit = try NativeLogicBitLowering().lower(word, context: &context)
            let candidate = try verify(bit, inputs: index == 0 ? 5 : 3, outputs: 2, context: &context)
            guard candidate.design.stateCount == 2 else { throw .invalidModel("Sequential state width changed") }
            let model = try NativeLogicSimulationCompiler().compile(rtl, context: &context)
            let evaluator = NativeLogicSimulationEvaluator()
            var state = try evaluator.makeState(model, context: &context)
            let events: [[UInt64]] = index == 0
                ? [[0,0,1,3],[0,1,1,3],[1,1,1,3],[0,1,0,0],[1,1,0,0],[1,0,0,0],[1,1,0,3]]
                : [[1,3],[0,0],[1,0]]
            let expected: [UInt64] = index == 0 ? [0,0,3,3,3,0,0] : [3,3,0]
            for step in events.indices {
                var updates: [LogicInputEvent.Update] = []
                for port in events[step].indices {
                    let width = port == events[step].count - 1 ? 2 : 1
                    let value = try LogicFourStateVector(width: .init(width), valueWords: [events[step][port]], unknownWords: [0])
                    updates.append(.init(portIndex: port, value: value))
                }
                let output = try evaluator.evaluate(model, event: .init(time: UInt64(step), updates: updates), state: &state, context: &context)
                for offset in 0..<2 {
                    guard try output.output(at: 0).value.bit(at: offset) == (expected[step] & (1 << offset) == 0 ? .zero : .one) else { throw .invalidModel("Sequential RTL event differs from its contract") }
                }
            }
        }
    }
    public static func exercise() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let identities = try identities(context: &context)
        let normalized = try verify(identities, inputs: 2, outputs: 14, context: &context)
        guard normalized.design.nodeCount == 6, normalized.statistics.constantFolds == 6,
              normalized.statistics.commonSubexpressions >= 1 else { throw .invalidModel("Boolean identities were not canonicalized") }
        for seed in 1...24 {
            let graph = try fixture(seed: UInt64(seed), context: &context)
            _ = try verify(graph, inputs: 3, outputs: 3, context: &context)
        }
        for latch in [false, true] { for synchronous in [false, true] {
            if latch && synchronous { continue }
            let graph = try F.state(latch: latch, loweredEnable: !latch, synchronousReset: synchronous, context: &context)
            let candidate = try verify(graph, inputs: 4, outputs: 1, context: &context)
            guard candidate.design.stateCount == graph.stateCount else { throw .invalidModel("Optimization removed state") }
        } }
        try sourceIntegration(context: &context)
        try sequentialSourceIntegration(context: &context)
        try DeclarationSemanticsContractProbe.exercise()
    }
}
