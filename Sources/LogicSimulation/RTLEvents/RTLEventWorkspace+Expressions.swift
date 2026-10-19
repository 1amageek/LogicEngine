import LogicIR
import LogicKernelCore

extension RTLEventWorkspace {
    func expression(_ root: RTLExpressionIndex, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        try plan.design.withExpressions { nodes, operands, _ throws(LogicKernelError) in
            expressionStack.removeAll(keepingCapacity: true)
            expressionStack.append(root.rawValue)
            while let index = expressionStack.last {
                try context.charge(.workUnits)
                if generations[index] == generation { expressionStack.removeLast(); continue }
                let node = nodes[index]
                var waiting = false
                for position in node.operands {
                    try context.charge(.workUnits)
                    let operand = operands[position].rawValue
                    if generations[operand] != generation {
                        expressionStack.append(operand); waiting = true; break
                    }
                }
                if waiting { continue }
                func operand(_ position: Int) throws(LogicKernelError) -> LogicFourStateVector {
                    guard let value = expressions[operands[node.operands.lowerBound + position].rawValue] else {
                        throw .invalidModel("RTL expression operand was not evaluated")
                    }
                    return value
                }
                let value: LogicFourStateVector
                switch node.operation {
                case .read(let signal): value = values[signal.rawValue]
                case .constant(let constant): value = constant
                default: value = try RTLFourStateOperation.evaluate(node, nodes: nodes, operands: operands, context: &context) {
                    position, _ throws(LogicKernelError) in try operand(position)
                }
                }
                expressions[index] = value; generations[index] = generation
                expressionStack.removeLast()
            }
            guard let value = expressions[root.rawValue] else { throw .invalidModel("RTL root was not evaluated") }
            return value
        }
    }
}
