import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicSynthesis
import LogicProof
import LogicSimulation
import LogicProofProbeSupport

extension TechnologyMappingContractProbe {
    public static func stableSelectionAndTopology() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let low = try cell(.and,id:100,area:1,context:&context)
        let high = try cell(.and,id:200,area:1,context:&context)
        let inv = try cell(.inverter,id:300,area:1,context:&context)
        for cells in [[high,low,inv],[inv,low,high]] {
            let library = try Self.library(cells,context:&context)
            let source = try LogicEquivalenceContractProbe.bit(context:&context)
            let result = try verify(source,library:library,context:&context)
            let chosen = try result.design.withTables { _, instances, _, _, _, _ throws(LogicKernelError) in
                guard instances.count == 1 else { throw .invalidModel("Unexpected tie fixture cover") }
                return try library.cell(at: instances[0].cell).id.rawValue
            }
            guard chosen == 100, result.statistics.combinationalDepth == 1 else { throw .invalidModel("Selection depends on library declaration order") }
        }
        let nand = try library([cell(.nand,id:100,area:1,context:&context)],context:&context)
        for seed: UInt64 in 1...8 {
            for reversed in [false,true] {
                let source = try LogicOptimizationContractProbe.fixture(seed: seed,reversedIDs:reversed,context:&context)
                _ = try verify(source,library:nand,context:&context)
            }
        }
    }
    public static func rejectWrongStateControls() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let source = try LogicEquivalenceContractProbe.state(context:&context)
        let nand = try cell(.nand,id:100,area:1,context:&context)
        for state in [
            try sequentialCell(asynchronous:false,context:&context),
            try sequentialCell(high:false,asynchronous:true,context:&context),
            try sequentialCell(asynchronous:true,resetHigh:true,context:&context),
            try sequentialCell(asynchronous:true,resetValue:true,context:&context),
            try sequentialCell(latch:true,asynchronous:true,context:&context)] {
            let library = try Self.library([nand,state],context:&context)
            var refused = false
            do throws(LogicKernelError) {
                _ = try NativeLogicTechnologyMapper().map(source,library:library,policy:policy(),context:&context)
            } catch {
                guard case .unsupported = error else { throw error }; refused = true
            }
            guard refused else { throw .invalidModel("Incompatible sequential cell was mapped") }
        }
        let missing = try library([cell(.and,id:100,area:1,context:&context)],context:&context)
        var refused = false
        let xor = try LogicEquivalenceContractProbe.bit(.xor,context:&context)
        do throws(LogicKernelError) { _ = try NativeLogicTechnologyMapper().map(xor,library:missing,policy:policy(),context:&context) }
        catch { guard case .unsupported = error else { throw error }; refused = true }
        guard refused else { throw .invalidModel("Inadequate function library was approximated") }
    }
    public static func tamperedPinsFailIndependentProof() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        let reference = try LogicEquivalenceContractProbe.bit(invertedSecond:true,context:&context)
        let library = try Self.library([cell(.asymmetric,id:100,area:1,context:&context),cell(.inverter,id:200,area:2,context:&context)],context:&context)
        let result = try verify(reference,library:library,context:&context)
        let tampered = try result.design.withTables { nets, instances, pins, ports, bits, _ throws(LogicKernelError) in
            var b = try MappedGateBuilder(library:library,capacity:.init(nets:nets.count,instances:instances.count,pinConnections:pins.count,ports:ports.count,portBits:bits.count),context:&context)
            for i in nets.indices { _ = try b.addNet(nets[i],context:&context) }
            for i in instances.indices {
                var bindings: [MappedNetIndex] = []
                for pi in instances[i].pins { bindings.append(pins[pi]) }
                bindings.swapAt(1,2)
                _ = try b.addInstance(id:instances[i].id,cell:instances[i].cell,pinNets:bindings,context:&context)
            }
            for i in ports.indices {
                var bindings: [MappedNetIndex] = []
                for pi in ports[i].bits { bindings.append(bits[pi]) }
                try b.addPort(id:ports[i].id,direction:ports[i].direction,nets:bindings,context:&context)
            }
            return try b.finish(context:&context)
        }
        let problem = try LogicEquivalenceContractProbe.problem(.bit(reference),.mapped(tampered),inputs:2,context:&context)
        guard case .different(let witness) = try NativeLogicEquivalenceChecker().check(problem,context:&context), witness.hasConcreteEventDifference else {
            throw .invalidModel("Swapped actual pins escaped independent replay")
        }
        try witness.requireBinding(to:problem)
        let and = try LogicEquivalenceContractProbe.bit(context:&context)
        let wrong = try LogicEquivalenceContractProbe.mapped(nand:true,context:&context)
        let wrongProblem = try LogicEquivalenceContractProbe.problem(.bit(and),.mapped(wrong),inputs:2,context:&context)
        guard case .different(let witness) = try NativeLogicEquivalenceChecker().check(wrongProblem,context:&context), witness.hasConcreteEventDifference else {
            throw .invalidModel("Wrong actual NAND function escaped independent replay")
        }
    }
}

extension TechnologyMappingContractProbe {
    public static func sixInputCutAndAbsorbedNodes() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        typealias F = LogicEquivalenceContractProbe
        var function = try LogicBooleanFunctionBuilder(inputCount:7,nodeCapacity:11,context:&context)
        var inputs: [LogicBooleanNodeIndex] = []
        for i in 0..<6 { inputs.append(try function.append(.input(i+1),context:&context)) }
        var value = inputs[0]
        for i in 1..<6 { value = try function.append(.and(value,inputs[i]),context:&context) }
        let truth = try function.finish(output:value,context:&context)
        var cell = try LogicTechnologyCellBuilder(id:F.id(100),name:"AND6",pinCapacity:7,context:&context)
        _ = try cell.append(.init(id:F.id(101),name:"Y",direction:.output,function:truth),context:&context)
        for i in 0..<6 { _ = try cell.append(.init(id:F.id(UInt64(102+i)),name:"I\(i)",direction:.input),context:&context) }
        let library = try Self.library([cell.finish(area:6,context:&context)],context:&context)
        var source = try BitLogicBuilder(capacity:.init(nodes:11,operands:10,ports:2,portBits:7,states:0),context:&context)
        var bits: [BitNodeIndex] = []
        for i in 0..<6 { bits.append(try source.addNode(id:F.id(UInt64(10-i)),operation:.input,context:&context)) }
        var output = bits[0]
        for i in 1..<6 { output = try source.addNode(id:F.id(UInt64(30-i)),operation:.and,inputs:[output,bits[i]],context:&context) }
        try source.addPort(id:F.id(200),direction:.input,bits:bits,context:&context)
        try source.addPort(id:F.id(201),direction:.output,bits:[output],context:&context)
        let bit = try source.finish(context:&context)
        let mapped = try NativeLogicTechnologyMapper().map(bit,library:library,policy:policy(inputs:6,cuts:8),context:&context)
        guard mapped.design.instanceCount == 1, mapped.statistics.combinationalDepth == 1 else { throw .invalidModel("Six-input cut was not absorbed into the actual cell") }
        let problem = try F.problem(.bit(bit),.mapped(mapped.design),inputs:6,context:&context)
        guard case .equivalent(let proof) = try NativeLogicEquivalenceChecker().check(problem,context:&context) else { throw .invalidModel("Six-input actual function was not proved") }
        try proof.requireBinding(to:problem)
    }
}
