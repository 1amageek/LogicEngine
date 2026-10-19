import LogicIR
import LogicKernelCore

extension RTLDependencyWorkspace {
    mutating func symbol(_ root: Int, bit: Int, expressions: borrowing Span<RTLResolvedExpression>,
                         operands: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        evaluation.truncate(0); try evaluation.append(.visit(root, bit), context: &context)
        while let task = evaluation.popLast() {
            try context.charge(.workUnits)
            switch task {
            case .visit(let index, let selected):
                let location = expressionOffsets[index] + selected
                if symbolEpoch[location] == epoch { continue }
                switch expressions[index].operation {
                case .read(let signal): symbolCache[location] = versions[offsets[signal.rawValue] + selected].symbol; symbolEpoch[location] = epoch
                case .constant(let value): symbolCache[location] = Int(try value.bit(at: selected).rawValue); symbolEpoch[location] = epoch
                default:
                    try evaluation.append(.finish(index, selected), context: &context)
                    for position in expressions[index].operands {
                        let child = operands[position].rawValue
                        for bit in 0..<expressions[child].type.width.value where symbolEpoch[expressionOffsets[child] + bit] != epoch {
                            try evaluation.append(.visit(child, bit), context: &context)
                        }
                    }
                }
            case .finish(let index, let selected):
                let expression = expressions[index]
                var constant = true
                for position in expression.operands {
                    let child = operands[position].rawValue
                    for bit in 0..<expressions[child].type.width.value {
                        try context.charge(.workUnits)
                        if symbolCache[expressionOffsets[child] + bit] >= 4 { constant = false }
                    }
                }
                if constant {
                    let value = try RTLFourStateOperation.evaluate(expression, nodes: expressions, operands: operands, context: &context) {
                        position, run throws(LogicKernelError) in
                        let child = operands[expression.operands.lowerBound + position].rawValue
                        let width = expressions[child].type.width
                        _ = try run.reserveStorage(byteCount: UInt64(width.wordCount) * 16)
                        var values = [UInt64](repeating: 0, count: width.wordCount)
                        var unknowns = [UInt64](repeating: 0, count: width.wordCount)
                        for bit in 0..<width.value {
                            try run.charge(.workUnits)
                            let digit = symbolCache[expressionOffsets[child] + bit]
                            values[bit / 64] |= UInt64(digit & 1) << (bit % 64)
                            unknowns[bit / 64] |= UInt64((digit >> 1) & 1) << (bit % 64)
                        }
                        return try LogicFourStateVector(width: width, valueWords: values, unknownWords: unknowns)
                    }
                    for bit in 0..<expression.type.width.value {
                        symbolCache[expressionOffsets[index] + bit] = Int(try value.bit(at: bit).rawValue)
                        symbolEpoch[expressionOffsets[index] + bit] = epoch
                    }
                    continue
                }
                var alias: Int?
                if case .compute(let op) = expression.operation {
                    let first = operands[expression.operands.lowerBound].rawValue
                    switch op {
                    case .bitcast: alias = symbolCache[expressionOffsets[first] + selected]
                    case .slice(let offset): alias = symbolCache[expressionOffsets[first] + selected + offset]
                    case .zeroExtend: alias = selected < expressions[first].type.width.value ? symbolCache[expressionOffsets[first] + selected] : 0
                    case .signExtend: alias = symbolCache[expressionOffsets[first] + min(selected, expressions[first].type.width.value - 1)]
                    case .concatenate:
                        var offset = 0
                        for position in expression.operands.reversed() {
                            let child = operands[position].rawValue; let width = expressions[child].type.width.value
                            if selected - offset < width { alias = symbolCache[expressionOffsets[child] + selected - offset]; break }
                            offset += width
                        }
                    default: break
                    }
                }
                let result: Int
                if let alias { result = alias }
                else {
                    guards.temporary.truncate(0)
                    for position in expression.operands {
                        let child = operands[position].rawValue
                        for bit in 0..<expressions[child].type.width.value { try guards.temporary.append(symbolCache[expressionOffsets[child] + bit], context: &context) }
                    }
                    result = try guards.intern(expression: index, bit: selected, nodes: expressions, operands: operands, base: bitCount + 4, context: &context)
                }
                symbolCache[expressionOffsets[index] + selected] = result; symbolEpoch[expressionOffsets[index] + selected] = epoch
            }
        }
        return symbolCache[expressionOffsets[root] + bit]
    }
    mutating func caseGuard(selector: Int, match: Int, expressions: borrowing Span<RTLResolvedExpression>,
                            operands: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        // Evaluate first: symbol() also uses the guard temporary buffer internally.
        for position in 0..<2 {
            let expression = position == 0 ? selector : match
            for bit in 0..<expressions[expression].type.width.value { _ = try symbol(expression, bit: bit, expressions: expressions, operands: operands, context: &context) }
        }
        guards.temporary.truncate(0)
        var constant = true; var equal = true
        let width = expressions[selector].type.width.value
        for position in 0..<2 {
            let expression = position == 0 ? selector : match
            for bit in 0..<width { try guards.temporary.append(symbolCache[expressionOffsets[expression] + bit], context: &context) }
        }
        for bit in 0..<width {
            let a = guards.temporary[bit]; let b = guards.temporary[width + bit]
            constant = constant && a < 4 && b < 4; equal = equal && a == b
        }
        if equal { return 1 }; if constant { return 0 }
        for index in guards.symbols.indices {
            try context.charge(.workUnits)
            let candidate = guards.symbols[index]
            if candidate.expression != -1 || candidate.bit != width { continue }
            var same = true
            for bit in guards.temporary.indices {
                try context.charge(.workUnits)
                if guards.inputs[candidate.inputs.lowerBound + bit] != guards.temporary[bit] { same = false; break }
            }
            if same { return try guards.atom(bitCount + 4 + index, context: &context) }
        }
        let start = guards.inputs.count
        for index in guards.temporary.indices { try guards.inputs.append(guards.temporary[index], context: &context) }
        let result = try nextSymbolIdentity()
        try guards.symbols.append(.init(expression: -1, bit: width, inputs: start..<guards.inputs.count), context: &context)
        return try guards.atom(result, context: &context)
    }
    mutating func mergedSymbol(condition: Int, a: Int, b: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if a == b || condition == 0 { return a }; if condition == 1 { return b }
        for index in guards.symbols.indices {
            try context.charge(.workUnits)
            let record = guards.symbols[index]
            if record.expression == -2 && record.bit == condition && guards.inputs[record.inputs.lowerBound] == a && guards.inputs[record.inputs.lowerBound + 1] == b { return bitCount + 4 + index }
        }
        let start = guards.inputs.count
        try guards.inputs.append(a, context: &context); try guards.inputs.append(b, context: &context)
        let result = try nextSymbolIdentity()
        try guards.symbols.append(.init(expression: -2, bit: condition, inputs: start..<guards.inputs.count), context: &context)
        return result
    }

    func nextSymbolIdentity() throws(LogicKernelError) -> Int {
        let result = (bitCount + 4).addingReportingOverflow(guards.symbols.count)
        guard !result.overflow else { throw .invalidInput("RTL gate symbol identity exhausted") }
        return result.partialValue
    }

}
