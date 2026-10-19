import LogicIR
import LogicKernelCore

extension RTLDependencyWorkspace {
    mutating func dependency(_ root: Int, bit: Int, expressions: borrowing Span<RTLResolvedExpression>,
                             operands: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        evaluation.truncate(0); try evaluation.append(.visit(root, bit), context: &context)
        while let task = evaluation.popLast() {
            try context.charge(.workUnits)
            switch task {
            case .visit(let index, let selected):
                let location = expressionOffsets[index] + selected
                if cacheEpoch[location] == epoch { continue }
                switch expressions[index].operation {
                case .read(let signal): cache[location] = versions[offsets[signal.rawValue] + selected].environment; cacheEpoch[location] = epoch
                case .constant: cache[location] = -1; cacheEpoch[location] = epoch
                default:
                    try evaluation.append(.finish(index, selected), context: &context)
                    try RTLBitDependencyTransfer.visit(index, bit: selected, expressions: expressions, operands: operands, context: &context) {
                        child, bit, run throws(LogicKernelError) in
                        if cacheEpoch[expressionOffsets[child] + bit] != epoch { try evaluation.append(.visit(child, bit), context: &run) }
                    }
                }
            case .finish(let index, let selected):
                var result = -1
                try RTLBitDependencyTransfer.visit(index, bit: selected, expressions: expressions, operands: operands, context: &context) {
                    child, bit, run throws(LogicKernelError) in
                    let location = expressionOffsets[child] + bit
                    guard cacheEpoch[location] == epoch else { throw .invalidModel("RTL dependency operand was not evaluated") }
                    result = try union(result, cache[location], context: &run)
                }
                cache[expressionOffsets[index] + selected] = result; cacheEpoch[expressionOffsets[index] + selected] = epoch
            }
        }
        return cache[expressionOffsets[root] + bit]
    }
    mutating func predicate(_ root: Int, expressions: borrowing Span<RTLResolvedExpression>,
                            operands: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        var result = -1
        for bit in 0..<expressions[root].type.width.value {
            let value = try dependency(root, bit: bit, expressions: expressions, operands: operands, context: &context)
            result = try union(result, value, context: &context)
        }
        try markReads(result, context: &context)
        return result
    }
}
