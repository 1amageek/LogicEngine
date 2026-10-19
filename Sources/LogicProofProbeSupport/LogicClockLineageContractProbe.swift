import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicProof
import LogicSimulation

public enum LogicClockLineageContractProbe {
    private static func id(_ value: UInt64) throws(LogicKernelError) -> DesignEntityID {
        try LogicEquivalenceContractProbe.id(value)
    }
    private static func library(context: inout LogicKernelContext) throws(LogicKernelError) -> LogicTechnologyLibrary {
        var builder = try LogicTechnologyLibraryBuilder(cellCapacity: 5, totalPinCapacity: 13, context: &context)
        for index in 0..<5 {
            let stateful = index < 2; let count = stateful || index == 4 ? 3 : 2
            let base = UInt64(100 + index * 10)
            var function = try LogicBooleanFunctionBuilder(inputCount: count + (stateful ? 1 : 0), nodeCapacity: 3, context: &context)
            var output = try function.append(.input(stateful ? 3 : 1), context: &context)
            if index == 3 { output = try function.append(.invert(output), context: &context) }
            if index == 4 {
                let other = try function.append(.input(2), context: &context)
                output = try function.append(.and(output, other), context: &context)
            }
            let published = try function.finish(output: output, context: &context)
            var cell = try LogicTechnologyCellBuilder(id: id(base), name: "actual-function-\(index)", pinCapacity: count, context: &context)
            _ = try cell.append(.init(id: id(base + 1), name: "Y", direction: .output, function: published), context: &context)
            _ = try cell.append(.init(id: id(base + 2), name: "A", direction: .input), context: &context)
            if count == 3 { _ = try cell.append(.init(id: id(base + 3), name: "B", direction: .input), context: &context) }
            let definition: LogicCellStateDefinition?
            if stateful {
                var data = try LogicBooleanFunctionBuilder(inputCount: 4, nodeCapacity: 1, context: &context)
                let d = try data.append(.input(1), context: &context)
                definition = .init(control: .flipFlop(clock: .init(2), risingEdge: index == 0),
                    nextState: try data.finish(output: d, context: &context))
            } else { definition = nil }
            _ = try builder.append(cell.finish(area: 1, state: definition, context: &context), context: &context)
        }
        let source: ArtifactID
        do { source = try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "ca", count: 32)), byteCount: 1) }
        catch { throw .invalidInput("Invalid clock fixture source identity") }
        return try builder.finish(source: source, context: &context)
    }
    public static func bit(states count: Int = 2, inverted: Bool = false, falling: Bool = false, gated: Bool = false,
                           context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        var builder = try BitLogicBuilder(capacity: .init(nodes: 2 * count + 3, operands: 3,
            ports: count + 2, portBits: 2 * count + 1, states: count), context: &context)
        var inputs: [BitNodeIndex] = [], outputs: [BitNodeIndex] = []
        for index in 0...count { inputs.append(try builder.addNode(id: id(UInt64(10 + index)), operation: .input, context: &context)) }
        var clock = try builder.addNode(id: id(50), operation: gated ? .and : .buffer,
            inputs: gated ? [inputs[count], inputs[0]] : [inputs[count]], context: &context)
        if inverted { clock = try builder.addNode(id: id(51), operation: .invert, inputs: [clock], context: &context) }
        for index in 0..<count {
            outputs.append(try builder.addNode(id: id(UInt64(60 + index)), operation: .state(.init(index)), context: &context))
            _ = try builder.addState(.init(id: id(UInt64(4000 + index)), next: inputs[index],
                control: .flipFlop(clock: clock, edge: falling ? .falling : .rising, enable: nil, reset: nil)), context: &context)
        }
        for index in inputs.indices { try builder.addPort(id: id(UInt64(3000 + index)), direction: .input, bits: [inputs[index]], context: &context) }
        try builder.addPort(id: id(UInt64(3001 + count)), direction: .output, bits: outputs, context: &context)
        return try builder.finish(context: &context)
    }
    public static func mapped(steps: [[Bool]], rising: [Bool], roots: [Int]? = nil,
                              gated: Bool = false, cycle: Bool = false, wrongData: Bool = false,
                              context: inout LogicKernelContext) throws(LogicKernelError) -> MappedGateDesign {
        let count = steps.count
        guard count > 0, rising.count == count, roots == nil || roots?.count == count else { throw .invalidInput("Invalid clock fixture dimensions") }
        var bufferCount = gated ? 1 : 0
        for branch in steps { bufferCount += branch.count }
        let library = try library(context: &context)
        var graph = try MappedGateBuilder(library: library,
            capacity: .init(nets: 2 * count + 1 + bufferCount, instances: count + bufferCount,
                pinConnections: 3 * count + 2 * bufferCount + (gated ? 1 : 0), ports: count + 2, portBits: 2 * count + 1), context: &context)
        var nextNet = 0, nextInstance = 0
        for _ in 0...count { _ = try addNet(.input, next: &nextNet, graph: &graph, context: &context) }
        var outputs: [MappedNetIndex] = []
        for index in 0..<count { outputs.append(try addNet(.instanceOutput(.init(bufferCount + index), .init(0)), next: &nextNet, graph: &graph, context: &context)) }
        var sharedClock = MappedNetIndex(count)
        if gated {
            let net = try addNet(.instanceOutput(.init(nextInstance), .init(0)), next: &nextNet, graph: &graph, context: &context)
            _ = try graph.addInstance(id: id(UInt64(2000 + nextInstance)), cell: .init(4), pinNets: [net, sharedClock, .init(0)], context: &context)
            nextInstance += 1; sharedClock = net
        }
        var clocks: [MappedNetIndex] = []
        for branch in steps.indices {
            var source = roots.map { MappedNetIndex($0[branch]) } ?? sharedClock
            for offset in steps[branch].indices {
                let out = try addNet(.instanceOutput(.init(nextInstance), .init(0)), next: &nextNet, graph: &graph, context: &context)
                if cycle && branch == 0 && offset == 0 { source = .init(out.rawValue + 1) }
                _ = try graph.addInstance(id: id(UInt64(2000 + nextInstance)), cell: .init(steps[branch][offset] ? 3 : 2),
                    pinNets: [out, source], context: &context)
                nextInstance += 1; source = out
            }
            clocks.append(source)
        }
        for index in 0..<count {
            _ = try graph.addInstance(id: id(UInt64(2000 + nextInstance)), cell: .init(rising[index] ? 0 : 1),
                pinNets: [outputs[index], .init(wrongData ? (index + 1) % count : index), clocks[index]],
                stateID: id(UInt64(4000 + index)), context: &context)
            nextInstance += 1
        }
        for index in 0...count { try graph.addPort(id: id(UInt64(3000 + index)), direction: .input, nets: [.init(index)], context: &context) }
        try graph.addPort(id: id(UInt64(3001 + count)), direction: .output, nets: outputs, context: &context)
        return try graph.finish(context: &context)
    }
    private static func addNet(_ driver: MappedGateNet.Driver, next: inout Int, graph: inout MappedGateBuilder,
                               context: inout LogicKernelContext) throws(LogicKernelError) -> MappedNetIndex {
        let result = try graph.addNet(.init(id: id(UInt64(1000 + next)), driver: driver), context: &context)
        next += 1; return result
    }
    public static func exercise() throws(LogicKernelError) {
        let checker = NativeLogicEquivalenceChecker()
        let evaluator: any LogicBinaryEvaluating = NativeLogicBinaryEvaluator()
        for (steps, rising) in [([[false], [false]], [true, true]),
                                 ([[false, false], [false, false, false]], [true, true]),
                                 ([[true, true], [false]], [true, true]),
                                 ([[], [true]], [true, false]),
                                 ([[true], [true, false]], [false, false])] {
            var run = try LogicProofContractProbe.context()
            let reference = try bit(context: &run)
            let candidate = try mapped(steps: steps, rising: rising, context: &run)
            let problem = try LogicEquivalenceContractProbe.problem(.bit(reference), .mapped(candidate), inputs: 3, outputs: 2, context: &run)
            guard case .equivalent(let proof) = try checker.check(problem, context: &run) else { throw .invalidModel("Equivalent clock branches were not proved") }
            try proof.requireBinding(to: problem)
            let rechecked = try checker.recheck(problem, certificate: proof.proof.certificate, context: &run)
            try rechecked.requireBinding(to: problem)
            let inputs = [true, true, true], initial = [false, false]
            var previous: [Bool] = []
            for branch in steps { previous.append(branch.filter { $0 }.count % 2 == 1) }
            let actual = try evaluator.replayInitialEvent(.mapped(candidate), inputs: inputs.span, initialState: initial.span,
                previousControls: previous.span, context: &run)
            try actual.withStates { states throws(LogicKernelError) in
                guard states[0], states[1] else { throw .invalidModel("Actual physical clock histories did not capture") }
            }
        }
        try physicalEventOracle()
        try invertedBitClockAndLegacyGated()
        try refusalAndWitnesses()
        try historyFailures()
    }
    public static func physicalEventOracle() throws(LogicKernelError) {
        var run = try LogicProofContractProbe.context()
        let evaluator: any LogicBinaryEvaluating = NativeLogicBinaryEvaluator()
        let inputs = [true, true], initial = [false], invertedPrevious = [true]
        for rising in [false, true] {
            let graph = try mapped(steps: [[true]], rising: [rising], context: &run)
            let actual = try evaluator.replayInitialEvent(.mapped(graph), inputs: inputs.span, initialState: initial.span,
                previousControls: invertedPrevious.span, context: &run)
            try actual.withStates { states throws(LogicKernelError) in
                guard states[0] == !rising else { throw .invalidModel("Inverted physical pin edge was evaluated as a root edge") }
            }
            let scalar = try evaluator.replayInitialEvent(.mapped(graph), inputs: inputs.span, initialState: initial.span,
                previousControl: false, context: &run)
            try scalar.withStates { states throws(LogicKernelError) in
                guard !states[0] else { throw .invalidModel("Scalar physical history meaning changed") }
            }
        }
        let directFalling = try bit(states: 1, falling: true, context: &run)
        let fallingInputs = [true, false]
        let captured = try evaluator.replayInitialEvent(.bit(directFalling), inputs: fallingInputs.span,
            initialState: initial.span, previousControl: true, context: &run)
        try captured.withStates { states throws(LogicKernelError) in
            guard states[0] else { throw .invalidModel("Direct falling scalar history semantics changed") }
        }
    }
    public static func invertedBitClockAndLegacyGated() throws(LogicKernelError) {
        for gated in [false, true] {
            var run = try LogicProofContractProbe.context()
            let reference = try bit(inverted: !gated, falling: !gated, gated: gated, context: &run)
            let candidate = try mapped(steps: [[], []], rising: [true, true], gated: gated, context: &run)
            let problem = try LogicEquivalenceContractProbe.problem(.bit(reference), .mapped(candidate), inputs: 3, outputs: 2, context: &run)
            let checker = NativeLogicEquivalenceChecker()
            guard case .equivalent(let proof) = try checker.check(problem, context: &run) else { throw .invalidModel("Bit inverse or legacy opaque clock semantics changed") }
            _ = try checker.recheck(problem, certificate: proof.proof.certificate, context: &run)
        }
    }
    public static func refusalAndWitnesses() throws(LogicKernelError) {
        var run = try LogicProofContractProbe.context()
        let reference = try bit(context: &run)
        for (index, candidate) in [try mapped(steps: [[], [true]], rising: [true, false], wrongData: true, context: &run),
                          try mapped(steps: [[], []], rising: [true, true], roots: [0, 0], context: &run),
                          try mapped(steps: [[], []], rising: [true, true], gated: true, context: &run)].enumerated() {
            let problem = try LogicEquivalenceContractProbe.problem(.bit(reference), .mapped(candidate), inputs: 3, outputs: 2, context: &run)
            switch try NativeLogicEquivalenceChecker().check(problem, context: &run) {
            case .equivalent: throw .invalidModel("Wrong data or clock wiring became equivalent")
            case .different(let witness):
                try witness.requireBinding(to: problem)
                let controls: Void? = try witness.withEventControls { left, right throws(LogicKernelError) in
                    guard left.count == 2, right.count == 2 else { throw .invalidModel("Missing actual witness histories") }
                    if index == 0 {
                        guard left[0] == left[1], right[0] == left[0], right[1] != left[1], witness.previousControl == nil else {
                            throw .invalidModel("Mixed witness histories were collapsed to a scalar")
                        }
                    }
                }
                guard controls != nil else { throw .invalidModel("Confirmed FF witness has no event histories") }
            case .inconclusive:
                if index == 0 { throw .invalidModel("Wrong data with mixed clock parity lacked a concrete witness") }
            }
        }
        for (steps, rising, roots, cycle) in [([[false], [false]], [true, true], [2, 0], false),
                                             ([[], []], [true, true], [2, 3], false),
                                             ([[false, false], [false]], [true, true], [2, 2], true)] {
            var refused = false
            do throws(LogicKernelError) { _ = try mapped(steps: steps, rising: rising, roots: roots, cycle: cycle, context: &run) }
            catch {
                switch error { case .unsupported, .invalidModel: refused = true; default: throw error }
            }
            guard refused else { throw .invalidModel("Invalid multi-root, generated or cyclic clock was admitted") }
        }
        let wrongEdge = try mapped(steps: [[true], [true]], rising: [true, true], context: &run)
        var refused = false
        do throws(LogicKernelError) { _ = try LogicEquivalenceContractProbe.problem(.bit(reference), .mapped(wrongEdge), inputs: 3, outputs: 2, context: &run) }
        catch {
            switch error { case .unsupported: refused = true; default: throw error }
        }
        guard refused else { throw .invalidModel("Wrong effective edge was admitted for proof") }
    }
    private struct Cancelled: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) { throw .cancelled }
    }
    private struct Expired: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) { throw .deadlineExceeded }
    }
    public static func historyFailures() throws(LogicKernelError) {
        var source = try LogicProofContractProbe.context()
        let graph = try bit(context: &source)
        let evaluator: any LogicBinaryEvaluating = NativeLogicBinaryEvaluator()
        let inputs = [true, true, true], initial = [false, false], valid = [false, false]
        for invalid in [[Bool](), [false], [false, false, false]] {
            var run = try LogicProofContractProbe.context(); var refused = false
            do throws(LogicKernelError) {
                _ = try evaluator.replayInitialEvent(.bit(graph), inputs: inputs.span, initialState: initial.span,
                    previousControls: invalid.span, context: &run)
            } catch { guard case .invalidInput = error else { throw error }; refused = true }
            guard refused, run.usage[.allocationBytes] == 0 else { throw .invalidModel("Invalid histories allocated or passed") }
        }
        for control in [Cancelled() as any LogicRunControlling, Expired()] {
            var run = try LogicProofContractProbe.context(control: control); var refused = false
            do throws(LogicKernelError) {
                _ = try evaluator.replayInitialEvent(.bit(graph), inputs: inputs.span, initialState: initial.span,
                    previousControls: valid.span, context: &run)
            } catch {
                switch error { case .cancelled, .deadlineExceeded: refused = true; default: throw error }
            }
            guard refused, run.usage[.managedStorageBytes] == 0 else { throw .invalidModel("Stopped history replay passed or leaked scratch") }
        }
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100_000_000)) })
        limits[.workUnits] = 1
        var run = LogicKernelContext(limits: try .init(maximums: limits), control: LogicProofContractProbe.Control())
        var refused = false
        do throws(LogicKernelError) {
            _ = try evaluator.replayInitialEvent(.bit(graph), inputs: inputs.span, initialState: initial.span,
                previousControls: valid.span, context: &run)
        } catch { guard case .resourceLimit = error else { throw error }; refused = true }
        guard refused, run.usage[.managedStorageBytes] == 0 else { throw .invalidModel("Bounded history replay passed or leaked scratch") }
    }

}
