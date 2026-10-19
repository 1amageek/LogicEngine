import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct BitExpansionPlan {
    let capacity: BitGraphCapacity
    let bitCount: Int
    let maximumWidth: Int
    let workspaceBytes: UInt64

    init(nodes: borrowing Span<WordLogicNode>, operands: borrowing Span<WordNodeIndex>,
         ports: borrowing Span<WordLogicPort>, states: borrowing Span<WordLogicState>,
         context: inout LogicKernelContext) throws(LogicKernelError) {
        var gates = 2; var bits = 0; var maximumWidth = 1
        for index in nodes.indices {
            try context.charge(.workUnits)
            let node = nodes[index]; let width = node.type.width.value
            try context.observeBitWidth(UInt64(width))
            bits = try Self.add(bits, width, limit: context.limits[.expansion])
            maximumWidth = max(maximumWidth, width)
            var count = width
            switch node.operation {
            case .input, .state, .constant: break
            case .compute(let opcode):
                let firstWidth = nodes[operands[node.operands.lowerBound].rawValue].type.width.value
                switch opcode {
                case .negate, .subtract: count = try Self.multiply(6, width, limit: context.limits[.expansion])
                case .add: count = try Self.multiply(5, width, limit: context.limits[.expansion])
                case .multiply: count = try Self.add(try Self.multiply(6, try Self.multiply(width, width, limit: context.limits[.expansion]), limit: context.limits[.expansion]), width, limit: context.limits[.expansion])
                case .equal: count = try Self.add(try Self.multiply(2, firstWidth, limit: context.limits[.expansion]), 1, limit: context.limits[.expansion])
                case .lessThan: count = try Self.add(try Self.multiply(5, firstWidth, limit: context.limits[.expansion]), 2, limit: context.limits[.expansion])
                case .logicalNot: count = try Self.add(firstWidth, 1, limit: context.limits[.expansion])
                case .logicalAnd, .logicalOr:
                    let secondWidth = nodes[operands[node.operands.lowerBound + 1].rawValue].type.width.value
                    count = try Self.add(try Self.add(firstWidth, secondWidth, limit: context.limits[.expansion]), 1, limit: context.limits[.expansion])
                case .reduceAnd, .reduceOr, .reduceXor: count = firstWidth
                case .shiftLeft, .shiftRight:
                    let amountWidth = nodes[operands[node.operands.lowerBound + 1].rawValue].type.width.value
                    var stages = 0; var distance = 1
                    while distance < width && stages < amountWidth {
                        try context.charge(.workUnits)
                        stages += 1
                        if distance > Int.max / 2 { break }
                        distance *= 2
                    }
                    count = try Self.add(try Self.multiply(width, try Self.add(stages, 1, limit: context.limits[.expansion]), limit: context.limits[.expansion]), amountWidth, limit: context.limits[.expansion])
                default: break
                }
            }
            gates = try Self.add(gates, count, limit: context.limits[.expansion])
        }
        var portBits = 0
        for index in ports.indices {
            try context.charge(.workUnits)
            portBits = try Self.add(portBits, nodes[ports[index].value.rawValue].type.width.value, limit: context.limits[.expansion])
        }
        var stateBits = 0
        for index in states.indices {
            try context.charge(.workUnits)
            let state = states[index]
            stateBits = try Self.add(stateBits, nodes[state.next.rawValue].type.width.value, limit: context.limits[.expansion])

        }
        try context.require(.expansion, amount: UInt64(gates))
        capacity = try BitGraphCapacity(nodes: gates, operands: Self.multiply(gates, 3, limit: context.limits[.expansion]),
                                       ports: ports.count, portBits: portBits, states: stateBits)
        bitCount = bits; self.maximumWidth = maximumWidth
        let indexCount = try Self.add(try Self.add(nodes.count, states.count, limit: context.limits[.expansion]), 2, limit: context.limits[.expansion])
        let bindingCount = try Self.add(try Self.add(bits, Self.multiply(maximumWidth, 3, limit: context.limits[.expansion]), limit: context.limits[.expansion]), 3, limit: context.limits[.expansion])
        let offsetBytes = try Self.multiply(indexCount, MemoryLayout<Int>.stride, limit: context.limits[.expansion])
        let bindingBytes = try Self.multiply(bindingCount, MemoryLayout<BitNodeIndex>.stride, limit: context.limits[.expansion])
        workspaceBytes = UInt64(try Self.add(offsetBytes, bindingBytes, limit: context.limits[.expansion]))
    }

    static func add(_ lhs: Int, _ rhs: Int, limit: UInt64) throws(LogicKernelError) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw .resourceLimit(resource: .expansion, limit: limit, requested: nil) }
        return result.partialValue
    }

    static func multiply(_ lhs: Int, _ rhs: Int, limit: UInt64) throws(LogicKernelError) -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw .resourceLimit(resource: .expansion, limit: limit, requested: nil) }
        return result.partialValue
    }
}
