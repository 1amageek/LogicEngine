import CircuiteFoundation
import LogicIR
import LogicKernelCore

internal struct MappingCoverWorkspace: ~Copyable {
    var cuts: [[MappingCut]]
    var solutions: [MappingSolution?]
    let maximumInputs: Int
    let maximumCuts: Int
    init(nodeCount: Int, policy: borrowing LogicMappingPolicy) {
        cuts = .init(repeating: [], count: nodeCount); solutions = .init(repeating: nil, count: nodeCount)
        maximumInputs = policy.maximumCutInputs; maximumCuts = policy.maximumCutsPerNode
    }
    private func lifted(_ cut: borrowing MappingCut, into leaves: borrowing [Int], context: inout LogicKernelContext)
        throws(LogicKernelError) -> UInt64 {
        var result: UInt64 = 0
        for row in 0..<(1 << leaves.count) {
            try context.charge(.workUnits)
            var sourceRow = 0
            for index in cut.leaves.indices {
                guard let offset = leaves.firstIndex(of: cut.leaves[index]) else { throw .invalidModel("Cut lost a leaf") }
                if row & (1 << offset) != 0 { sourceRow |= 1 << index }
            }
            if cut.truth & (UInt64(1) << sourceRow) != 0 { result |= UInt64(1) << row }
        }
        return result
    }
    private func combine(_ children: borrowing [MappingCut], operation: BitOperation,
                         context: inout LogicKernelContext) throws(LogicKernelError) -> MappingCut? {
        var leaves: [Int] = []; leaves.reserveCapacity(maximumInputs)
        for childIndex in children.indices {
            for leaf in children[childIndex].leaves {
                try context.charge(.workUnits)
                if !leaves.contains(leaf) {
                    guard leaves.count < maximumInputs else { return nil }; leaves.append(leaf)
                }
            }
        }
        leaves.sort()
        var masks: [UInt64] = []; masks.reserveCapacity(3)
        for childIndex in children.indices { masks.append(try lifted(children[childIndex], into: leaves, context: &context)) }
        let mask = MappingArithmetic.mask(leaves.count); let truth: UInt64
        switch operation {
        case .constant(let b): truth = b ? mask : 0
        case .buffer: truth = masks[0]
        case .invert: truth = masks[0] ^ mask
        case .and: truth = masks[0] & masks[1]
        case .or: truth = masks[0] | masks[1]
        case .xor: truth = masks[0] ^ masks[1]
        case .select: truth = (masks[0] & masks[1]) | ((masks[0] ^ mask) & masks[2])
        default: throw .invalidModel("Terminal operation cannot combine cuts")
        }
        return .init(leaves: leaves, truth: truth)
    }
    private func preferable(_ value: MappingSolution, to old: MappingSolution?, matcher: borrowing MappingFunctionMatcher,
                            inverter: MappingMatch?) throws(LogicKernelError) -> Bool {
        guard let old else { return true }
        if value.area != old.area { return value.area < old.area }
        if value.depth != old.depth { return value.depth < old.depth }
        func key(_ solution: borrowing MappingSolution) throws(LogicKernelError) -> (UInt64, [Int]) {
            switch solution.implementation {
            case .cell(let match): return (try matcher.library.cell(at: match.cell).id.rawValue, match.bindings)
            case .alias(let node, let inverted): return (inverted ? try matcher.library.cell(at: inverter!.cell).id.rawValue : 0, [node, inverted ? 1 : 0])
            default: return (0, [])
            }
        }
        let a = try key(value); let b = try key(old)
        if a.0 != b.0 { return a.0 < b.0 }
        if a.1 != b.1 { return a.1.lexicographicallyPrecedes(b.1) }
        return value.cut.leaves.lexicographicallyPrecedes(old.cut.leaves)
    }
    mutating func build(_ graph: borrowing MappingGraph, matcher: inout MappingFunctionMatcher,
                        inverter: MappingMatch?, context: inout LogicKernelContext) throws(LogicKernelError) {
        try graph.withTables { nodes, operands, _, _, _, order throws(LogicKernelError) in
            for position in order.indices {
                try context.charge(.workUnits); let index = order[position].rawValue; let node = nodes[index]
                switch node.operation {
                case .input, .state:
                    let terminal = MappingCut(leaves: [index], truth: 2); cuts[index] = [terminal]
                    solutions[index] = .init(cut: terminal, implementation: .terminal, area: 0, depth: 0)
                    continue
                default: break
                }
                var generated: [MappingCut] = []; generated.reserveCapacity(maximumCuts)
                var positions = [Int](repeating: 0, count: node.inputs.count)
                var done = false
                while !done && generated.count < maximumCuts {
                    try context.charge(.workUnits)
                    let transientBytes = 3 * MemoryLayout<MappingCut>.stride + 6 * MemoryLayout<Int>.stride + 3 * MemoryLayout<UInt64>.stride
                    let receipt = try context.reserveStorage(byteCount: UInt64(transientBytes))
                    do throws(LogicKernelError) {
                        var children: [MappingCut] = []; children.reserveCapacity(3)
                        for offset in positions.indices { children.append(cuts[node.inputs[offset].rawValue][positions[offset]]) }
                        if let cut = try combine(children, operation: node.operation, context: &context), !generated.contains(cut) { generated.append(cut) }
                    } catch { try context.releaseStorage(receipt); throw error }
                    try context.releaseStorage(receipt)
                    var digit = 0
                    while digit < positions.count {
                        positions[digit] += 1
                        if positions[digit] < cuts[node.inputs[digit].rawValue].count { break }
                        positions[digit] = 0; digit += 1
                    }
                    done = digit == positions.count
                }
                for cut in generated {
                    try context.charge(.workUnits)
                    var candidate: MappingSolution?
                    let mask = MappingArithmetic.mask(cut.leaves.count)
                    if cut.truth == 0 || cut.truth == mask {
                        candidate = .init(cut: .init(leaves: [], truth: cut.truth == 0 ? 0 : 1), implementation: .constant(cut.truth != 0), area: 0, depth: 0)
                    } else {
                        for leaf in cut.leaves.indices {
                            let v = MappingArithmetic.variable(leaf, count: cut.leaves.count)
                            let inverted = cut.truth != v && cut.truth == v ^ mask
                            if (cut.truth == v || (inverted && inverter != nil)), let source = solutions[cut.leaves[leaf]] {
                                candidate = .init(cut: .init(leaves: [cut.leaves[leaf]], truth: inverted ? 1 : 2),
                                    implementation: .alias(cut.leaves[leaf], inverted: inverted),
                                    area: source.area + (inverted ? inverter!.area : 0), depth: source.depth + (inverted ? inverter!.depth : 0))
                                break
                            }
                        }
                        if candidate == nil, let match = try matcher.combinational(truth: cut.truth, count: cut.leaves.count, inverter: inverter, context: &context) {
                            var area = match.area; var depth = 0; var complete = true
                            for leaf in cut.leaves {
                                if let child = solutions[leaf] { area += child.area; depth = max(depth, child.depth) }
                                else { complete = false }
                            }
                            guard area.isFinite else { throw .invalidModel("Mapping cover area overflows") }
                            if complete { candidate = .init(cut: cut, implementation: .cell(match), area: area, depth: depth + match.depth) }
                        }
                    }
                    if let candidate {
                        if try preferable(candidate, to: solutions[index], matcher: matcher, inverter: inverter) { solutions[index] = candidate }
                    }
                }
                // The terminal cut permits a parent's larger cell to absorb an unmapped node.
                var retained: [MappingCut] = []; retained.reserveCapacity(maximumCuts + 1)
                retained.append(.init(leaves: [index], truth: 2))
                for cut in generated { retained.append(cut) }
                cuts[index] = retained
            }
        }
    }
}
