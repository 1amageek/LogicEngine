import LogicIR
import LogicKernelCore
import LogicSimulation

internal struct EquivalenceShape: Sendable {
    let inputs: Int
    let outputs: Int
    let initials: [Bool?]
    let kinds: [LogicBinaryStateAction.Kind]
    let controlInversions: [Bool]
    static func describe(_ design: borrowing LogicBinaryDesign, context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        let stride = MemoryLayout<Bool?>.stride + MemoryLayout<LogicBinaryStateAction.Kind>.stride + MemoryLayout<Bool>.stride
        let payload = UInt64(design.stateCount).multipliedReportingOverflow(by: UInt64(stride))
        guard !payload.overflow else { throw .invalidInput("Equivalence shape capacity overflows") }
        _ = try context.reserveStorage(byteCount: payload.partialValue)
        var input = 0; var output = 0
        var initials: [Bool?] = []; initials.reserveCapacity(design.stateCount)
        var kinds: [LogicBinaryStateAction.Kind] = []; kinds.reserveCapacity(design.stateCount)
        var inversions: [Bool] = []; inversions.reserveCapacity(design.stateCount)
        func count(_ amount: Int, input isInput: Bool) throws(LogicKernelError) {
            try context.charge(.workUnits)
            let sum = (isInput ? input : output).addingReportingOverflow(amount)
            guard !sum.overflow else { throw .invalidInput("Equivalence interface dimension overflows") }
            if isInput { input = sum.partialValue } else { output = sum.partialValue }
        }
        switch design {
        case .bit(let graph):
            return try graph.withTables { (nodes: borrowing Span<BitLogicNode>, operands: borrowing Span<BitNodeIndex>, ports: borrowing Span<BitLogicPort>, _: borrowing Span<BitNodeIndex>, states: borrowing Span<BitLogicState>, _: borrowing Span<BitNodeIndex>) throws(LogicKernelError) in
                for index in ports.indices { try count(ports[index].bits.count, input: ports[index].direction == .input) }
                for index in states.indices {
                    try context.charge(.workUnits); initials.append(states[index].initialValue)
                    switch states[index].control {
                    case .flipFlop(let clock, let edge, _, _):
                        let inverted = try bitControlInversion(clock, nodes: nodes, operands: operands, context: &context)
                        inversions.append(inverted); kinds.append(.flipFlop(risingEdge: (edge == .rising) != inverted))
                    case .latch: inversions.append(false); kinds.append(.latch)
                    }
                }
                return Self(inputs: input, outputs: output, initials: initials, kinds: kinds, controlInversions: inversions)
            }
        case .mapped(let graph):
            try NativeMappedGateRealizationValidator().validate(graph, policy: .standardNetlist, context: &context)
            return try graph.withStateClocks { clocks throws(LogicKernelError) in
                try graph.withTables { _, instances, _, ports, _, _ throws(LogicKernelError) in
                    var clockOrdinal = 0
                    for index in ports.indices { try count(ports[index].bits.count, input: ports[index].direction == .input) }
                    for index in instances.indices {
                        try context.charge(.workUnits)
                        if let state = try graph.library.cell(at: instances[index].cell).state {
                            initials.append(instances[index].initialValue)
                            switch state.control {
                            case .flipFlop:
                                guard clockOrdinal < clocks.count, clocks[clockOrdinal].instance.rawValue == index else {
                                    throw .invalidModel("Mapped clock lineage does not cover sequential instances")
                                }
                                switch clocks[clockOrdinal].lineage {
                                case .primaryInput(_, let inverted, let rising):
                                    inversions.append(inverted); kinds.append(.flipFlop(risingEdge: rising))
                                case .opaque(_, let rising):
                                    inversions.append(false); kinds.append(.flipFlop(risingEdge: rising))
                                }
                                clockOrdinal += 1
                            case .latch: inversions.append(false); kinds.append(.latch)
                            }
                        }
                    }
                    guard clockOrdinal == clocks.count else { throw .invalidModel("Unowned mapped clock lineage") }
                    return Self(inputs: input, outputs: output, initials: initials, kinds: kinds, controlInversions: inversions)
                }
            }
        }
    }
    private static func bitControlInversion(_ clock: BitNodeIndex, nodes: borrowing Span<BitLogicNode>,
                                            operands: borrowing Span<BitNodeIndex>, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        var index = clock.rawValue; var inverted = false
        for _ in nodes.indices {
            try context.charge(.workUnits)
            switch nodes[index].operation {
            case .input: return inverted
            case .buffer: index = operands[nodes[index].operands.lowerBound].rawValue
            case .invert: inverted.toggle(); index = operands[nodes[index].operands.lowerBound].rawValue
            default: return false
            }
        }
        throw .invalidModel("Bit clock trace did not terminate in the validated graph")
    }
}
