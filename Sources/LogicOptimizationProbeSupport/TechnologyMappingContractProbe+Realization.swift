import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicSynthesis
import LogicSimulation
import LogicProof
import LogicProofProbeSupport

extension TechnologyMappingContractProbe {
    public static func startupAndPhysicalTies() throws(LogicKernelError) {
        var run = try LogicProofContractProbe.context()
        let low = try constantFunction(false, context: &run)
        let high = try constantFunction(true, context: &run)
        var cell = try LogicTechnologyCellBuilder(id: LogicEquivalenceContractProbe.id(500), name: "DUAL_TIE", pinCapacity: 2, context: &run)
        _ = try cell.append(.init(id: LogicEquivalenceContractProbe.id(501), name: "LO", direction: .output, function: low), context: &run)
        _ = try cell.append(.init(id: LogicEquivalenceContractProbe.id(502), name: "HI", direction: .output, function: high), context: &run)
        let actualLibrary = try library([cell.finish(area: 2, context: &run)], context: &run)
        var builder = try BitLogicBuilder(capacity: .init(nodes: 2, operands: 0, ports: 1, portBits: 4, states: 0), context: &run)
        let zero = try builder.addNode(id: LogicEquivalenceContractProbe.id(1), operation: .constant(false), context: &run)
        let one = try builder.addNode(id: LogicEquivalenceContractProbe.id(2), operation: .constant(true), context: &run)
        try builder.addPort(id: LogicEquivalenceContractProbe.id(3), direction: .output, bits: [zero, one, zero, one], context: &run)
        let source = try builder.finish(context: &run)
        let policy = try LogicMappingPolicy(maximumCutInputs: 3, maximumCellInputs: 3, maximumCutsPerNode: 8,
            firstEntityID: LogicEquivalenceContractProbe.id(10_000), realizationPolicy: .physicalCells)
        let mapped = try NativeLogicTechnologyMapper().map(source, library: actualLibrary, policy: policy, context: &run)
        guard mapped.design.instanceCount == 1, mapped.design.netCount == 2, mapped.statistics.area == 2 else {
            throw .invalidModel("Both actual tie outputs were not reused")
        }
        try NativeMappedGateRealizationValidator().validate(mapped.design, policy: .physicalCells, context: &run)
        let problem = try LogicEquivalenceContractProbe.problem(.bit(source), .mapped(mapped.design), inputs: 0, outputs: 4, context: &run)
        guard case .equivalent(let proof) = try NativeLogicEquivalenceChecker().check(problem, context: &run) else {
            throw .invalidModel("Actual tie-cell functions were not independently proved")
        }
        try proof.requireBinding(to: problem)
        let withoutTies = try library([Self.cell(.nand, id: 100, area: 1, context: &run)], context: &run)
        do throws(LogicKernelError) {
            _ = try NativeLogicTechnologyMapper().map(source, library: withoutTies, policy: policy, context: &run)
            throw .invalidModel("Missing physical tie capability was accepted")
        } catch .unsupported {} catch { throw error }
        let logical = try NativeLogicTechnologyMapper().map(source, library: withoutTies, policy: Self.policy(), context: &run)
        guard logical.design.instanceCount == 0 else { throw .invalidModel("Standard constants were unnecessarily materialized") }
        for initial in [false, true] {
            for latch in [false, true] {
                let state = try LogicEquivalenceContractProbe.state(latch: latch, initial: initial, context: &run)
                let cells = try library([Self.cell(.nand, id: 100, area: 1, context: &run),
                    sequentialCell(latch: latch, asynchronous: true, context: &run)], context: &run)
                do throws(LogicKernelError) {
                    _ = try NativeLogicTechnologyMapper().map(state, library: cells, policy: Self.policy(), context: &run)
                    throw .invalidModel("Mapping invented physical startup")
                } catch .unsupported {} catch { throw error }
                let sidecar = try LogicEquivalenceContractProbe.mappedState(latch: latch, initial: initial, context: &run)
                do throws(LogicKernelError) {
                    _ = try LogicEquivalenceContractProbe.problem(.bit(state), .mapped(sidecar), inputs: 4, context: &run)
                    throw .invalidModel("Actual-cell proof trusted startup metadata")
                } catch .unsupported {} catch { throw error }
                let omitted = try LogicEquivalenceContractProbe.mappedState(latch: latch, context: &run)
                do throws(LogicKernelError) {
                    _ = try LogicEquivalenceContractProbe.problem(.bit(state), .mapped(omitted), inputs: 4, context: &run)
                    throw .invalidModel("Actual-cell proof allowed initial demand removal")
                } catch .invalidInput {} catch { throw error }
            }
        }
    }

    private static func constantFunction(_ value: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBooleanFunction {
        var function = try LogicBooleanFunctionBuilder(inputCount: 2, nodeCapacity: 2, context: &context)
        let zero = try function.append(.constant(false), context: &context)
        let output = value ? try function.append(.invert(zero), context: &context) : zero
        return try function.finish(output: output, context: &context)
    }
}
