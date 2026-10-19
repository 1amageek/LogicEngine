import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func evaluate(_ root: Int, expressions: borrowing Span<RTLResolvedExpression>,
                           inputs: borrowing Span<RTLExpressionIndex>, current: Bool = true,
                           context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let generation = expressionGeneration.addingReportingOverflow(1)
        guard !generation.overflow else {
            throw .resourceLimit(resource: .workUnits, limit: context.limits[.workUnits], requested: nil)
        }
        expressionGeneration = generation.partialValue
        try expressionStack.append((root, false), receipt: &receipt, bytes: &bytes, context: &context)
        while let (index, ready) = expressionStack.popLast() {
            try context.charge(.workUnits)
            if cached[index].stamp == expressionGeneration { continue }
            if let override = resetOverride, override.expression == index {
                cached[index] = CachedExpression(stamp: expressionGeneration, value: override.value); continue
            }
            let expression = expressions[index]
            if let override = resetOverride, case .read(let signal) = expression.operation,
               case .read(let resetSignal) = expressions[override.expression].operation, signal == resetSignal {
                cached[index] = CachedExpression(stamp: expressionGeneration, value: override.value); continue
            }
            if !ready && !expression.operands.isEmpty {
                try expressionStack.append((index, true), receipt: &receipt, bytes: &bytes, context: &context)
                for offset in expression.operands.reversed() {
                    try expressionStack.append((inputs[offset].rawValue, false), receipt: &receipt, bytes: &bytes, context: &context)
                }
                continue
            }
            let value: Int
            switch expression.operation {
            case .read(let signal): value = try readSignal(signal.rawValue, current: current, context: &context)
            case .constant(let vector):
                guard vector.isTwoState else { throw failure("Synthesis expression depends on X/Z", origin: expression.origin) }
                value = try emit(type: expression.type, operation: .constant(vector), origin: expression.origin, context: &context)
            case .compute(let opcode):
                if opcode == .concatenate {
                    var combined: LogicFourStateVector?
                    for offset in expression.operands {
                        try context.charge(.workUnits)
                        guard case .constant(let element) = nodes[cached[inputs[offset].rawValue].value].operation else {
                            combined = nil; break
                        }
                        if let previous = combined { combined = try previous.concatenatingBinary(element, context: &context) }
                        else { combined = element }
                    }
                    if let combined {
                        value = try emit(type: expression.type, operation: .constant(combined), origin: expression.origin, context: &context)
                        cached[index] = CachedExpression(stamp: expressionGeneration, value: value)
                        continue
                    }
                    let start = operands.count
                    for offset in expression.operands {
                        try context.charge(.workUnits)
                        try operands.append(cached[inputs[offset].rawValue].value, receipt: &receipt, bytes: &bytes, context: &context)
                    }
                    value = nodes.count
                    try context.charge(.expansion)
                    try nodes.append(DraftNode(type: expression.type, operation: .compute(opcode), operands: start..<operands.count,
                        origin: expression.origin), receipt: &receipt, bytes: &bytes, context: &context)
                } else {
                    let count = expression.operands.count; let start = expression.operands.lowerBound
                    let a = cached[inputs[start].rawValue].value
                    let b = count > 1 ? cached[inputs[start + 1].rawValue].value : -1
                    let c = count > 2 ? cached[inputs[start + 2].rawValue].value : -1
                    value = try compute(opcode, type: expression.type, a: a, b: b, c: c,
                                        origin: expression.origin, context: &context)
                }
            case .caseEqual:
                value = try compute(.equal, type: scalar,
                    a: cached[inputs[expression.operands.lowerBound].rawValue].value,
                    b: cached[inputs[expression.operands.lowerBound + 1].rawValue].value,
                    origin: expression.origin, context: &context)
            case .dynamicSelect:
                let a = cached[inputs[expression.operands.lowerBound].rawValue].value
                let b = cached[inputs[expression.operands.lowerBound + 1].rawValue].value
                value = try dynamicSelect(a, offset: b, type: expression.type, origin: expression.origin, context: &context)
            }
            cached[index] = CachedExpression(stamp: expressionGeneration, value: value)
        }
        return cached[root].value
    }

    mutating func compute(_ opcode: WordLogicOpcode, type: WordLogicType, a: Int, b: Int = -1, c: Int = -1,
                          origin: LogicKernelSourceRange?, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if opcode == .select { return try select(a, b, c, origin: origin, context: &context) }
        if let value = try constantCompute(opcode, type: type, a: a, b: b, origin: origin, context: &context) { return value }
        if opcode == .slice(offset: 0) && type == nodes[a].type { return a }
        if case .slice(let offset) = opcode, type == scalar { return try bit(a, at: offset, context: &context) }
        if opcode == .bitcast && type == nodes[a].type { return a }
        if opcode == .logicalNot, nodes[a].type == scalar {
            if let value = booleanConstant(a) { return value ? 0 : 1 }
            return try control(1, a: a, origin: origin, context: &context)
        }
        if opcode == .logicalAnd || opcode == .and, type == scalar {
            if a == b { return a }
            if let value = booleanConstant(a) { return value ? b : 0 }
            if let value = booleanConstant(b) { return value ? a : 0 }
            return try control(3, a: min(a, b), b: max(a, b), origin: origin, context: &context)
        }
        if opcode == .logicalOr || opcode == .or, type == scalar {
            if a == b { return a }
            if let value = booleanConstant(a) { return value ? 1 : b }
            if let value = booleanConstant(b) { return value ? 1 : a }
            return try control(2, a: min(a, b), b: max(a, b), origin: origin, context: &context)
        }
        if opcode == .equal, case .constant(let av) = nodes[a].operation,
           case .constant(let bv) = nodes[b].operation {
            try context.charge(.workUnits, amount: UInt64(av.width.wordCount))
            return av == bv ? 1 : 0
        }
        return try emit(type: type, operation: .compute(opcode), a: a, b: b, c: c, origin: origin, context: &context)
    }

    mutating func dynamicSelect(_ vector: Int, offset: Int, type: WordLogicType,
                                origin: LogicKernelSourceRange?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        let maximum = nodes[vector].type.width.value - type.width.value
        guard maximum >= 0 else { throw failure("Dynamic selection can produce X outside its vector", origin: origin) }
        if case .constant(let value) = nodes[offset].operation {
            let selected: Int
            do throws(LogicKernelError) { selected = try value.binaryInt(signed: nodes[offset].type.isSigned, context: &context) }
            catch {
                guard case .invalidModel = error else { throw error }
                throw failure("Dynamic selection offset is outside its vector", origin: origin)
            }
            guard selected >= 0 && selected <= maximum else { throw failure("Dynamic selection offset is outside its vector", origin: origin) }
            return try compute(.slice(offset: selected), type: type, a: vector, origin: origin, context: &context)
        }
        let indexType = nodes[offset].type
        guard !indexType.isSigned, indexType.width.value < Int.bitWidth - 1,
              (1 << indexType.width.value) - 1 <= maximum else {
            throw failure("Dynamic selection lacks a binary in-range offset guarantee", origin: origin)
        }
        let shifted = try emit(type: nodes[vector].type, operation: .compute(.shiftRight(arithmetic: false)),
                               a: vector, b: offset, origin: origin, context: &context)
        return try compute(.slice(offset: 0), type: type, a: shifted, origin: origin, context: &context)
    }
}
