import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func verifyRaces(context: inout LogicKernelContext) throws(LogicKernelError) {
        // Reads are checked after all combinational aliases are resolved, so an
        // intermediate wire cannot hide an Active-region FF blocking-write race.
        for index in states.indices {
            guard let state = states[index] else { throw .invalidModel("Unresolved retained RTL state") }
            guard case .flipFlop(let clock, _, let enable, let reset) = state.control else { continue }
            let reader = bits[stateBits[index]].writer
            try verifyRaceRoot(state.next.rawValue, reader: reader, context: &context)
            try verifyRaceRoot(clock.rawValue, reader: reader, context: &context)
            if let enable { try verifyRaceRoot(enable.rawValue, reader: reader, context: &context) }
            if let reset { try verifyRaceRoot(reset.signal.rawValue, reader: reader, context: &context) }
        }
    }

    mutating func demand(_ value: Int, _ range: Range<Int>, context: inout LogicKernelContext) throws(LogicKernelError) {
        if !range.isEmpty { try demands.append((value, range), receipt: &receipt, bytes: &bytes, context: &context) }
    }

    mutating func verifyRaceRoot(_ root: Int, reader: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        seenDemands.truncate(0)
        try demand(root, 0..<nodes[root].type.width.value, context: &context)
        while let (index, range) = demands.popLast() {
            try context.charge(.workUnits)
            var seen = false
            for previous in seenDemands.indices {
                try context.charge(.workUnits)
                let old = seenDemands[previous]
                if old.0 == index, old.1.lowerBound <= range.lowerBound, old.1.upperBound >= range.upperBound {
                    seen = true; break
                }
            }
            if seen { continue }
            try seenDemands.append((index, range), receipt: &receipt, bytes: &bytes, context: &context)
            let node = nodes[index]
            if let alias = node.alias { try demand(alias, range, context: &context); continue }
            switch node.operation {
            case .state(let state):
                let bit = bits[stateBits[state.rawValue]]
                if bit.writer != reader && bit.blockingFFWriter {
                    throw failure("FF processes have an Active-region blocking read/write race", origin: node.origin)
                }
            case .compute(let opcode):
                let a = operands[node.operands.lowerBound]
                switch opcode {
                case .bitcast, .invert:
                    try demand(a, range, context: &context)
                case .zeroExtend, .signExtend:
                    let width = nodes[a].type.width.value
                    if range.lowerBound < width { try demand(a, range.lowerBound..<min(range.upperBound, width), context: &context) }
                    if opcode == .signExtend && range.upperBound > width { try demand(a, (width - 1)..<width, context: &context) }
                case .slice(let offset):
                    try demand(a, (offset + range.lowerBound)..<(offset + range.upperBound), context: &context)
                case .concatenate:
                    var offset = 0
                    for position in node.operands.reversed() {
                        let source = operands[position]; let width = nodes[source].type.width.value
                        let low = max(range.lowerBound, offset); let high = min(range.upperBound, offset + width)
                        if low < high { try demand(source, (low - offset)..<(high - offset), context: &context) }
                        offset += width
                    }
                case .and, .or, .xor:
                    try demand(a, range, context: &context)
                    try demand(operands[node.operands.lowerBound + 1], range, context: &context)
                case .add, .subtract, .multiply, .negate:
                    for position in node.operands { try demand(operands[position], 0..<range.upperBound, context: &context) }
                case .select:
                    try demand(a, 0..<1, context: &context)
                    try demand(operands[node.operands.lowerBound + 1], range, context: &context)
                    try demand(operands[node.operands.lowerBound + 2], range, context: &context)
                case .logicalNot, .logicalAnd, .logicalOr, .reduceAnd, .reduceOr, .reduceXor,
                     .equal, .lessThan, .shiftLeft, .shiftRight:
                    for position in node.operands {
                        let source = operands[position]
                        try demand(source, 0..<nodes[source].type.width.value, context: &context)
                    }
                }
            case .input, .constant, .none: break
            }
        }
    }
}
