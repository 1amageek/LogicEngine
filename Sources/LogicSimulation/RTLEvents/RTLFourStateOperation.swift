import LogicIR
import LogicKernelCore

internal enum RTLFourStateOperation {
    static func evaluate(_ node: RTLResolvedExpression, nodes: borrowing Span<RTLResolvedExpression>,
                         operands: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext,
                         operand: (Int, inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector)
        throws(LogicKernelError) -> LogicFourStateVector {
        let value: LogicFourStateVector
        switch node.operation {
        case .read: throw .invalidModel("Computed RTL operation cannot read signal storage")
        case .constant(let constant): value = constant
        case .caseEqual: value = try scalar(operand(0, &context).equalsFourState(operand(1, &context), caseEquality: true, context: &context), context: &context)
        case .dynamicSelect:
            let source = try operand(0, &context); let offset = try operand(1, &context)
            if let amount = try boundedOffset(offset, signed: nodes[operands[node.operands.lowerBound + 1].rawValue].type.isSigned, upperBound: source.width.value, context: &context), amount <= source.width.value - node.type.width.value {
                value = try source.slicingFourState(offset: amount, width: node.type.width, context: &context)
            } else { value = try .init(repeating: .unknown, width: node.type.width, context: &context) }
        case .compute(let opcode):
            let a = try operand(0, &context)
            switch opcode {
            case .bitcast: value = a
            case .zeroExtend: value = try a.resizedFourState(to: node.type.width, signExtend: false, context: &context)
            case .signExtend: value = try a.resizedFourState(to: node.type.width, signExtend: true, context: &context)
            case .invert: value = try a.invertingFourState(context: &context)
            case .negate: value = try a.negatingFourState(context: &context)
            case .and: value = try a.applyingFourState(.and, to: operand(1, &context), context: &context)
            case .or: value = try a.applyingFourState(.or, to: operand(1, &context), context: &context)
            case .xor: value = try a.applyingFourState(.xor, to: operand(1, &context), context: &context)
            case .add: value = try a.addingFourState(operand(1, &context), context: &context)
            case .subtract: value = try a.subtractingFourState(operand(1, &context), context: &context)
            case .multiply: value = try a.multiplyingFourState(operand(1, &context), context: &context)
            case .equal: value = try scalar(a.equalsFourState(operand(1, &context), context: &context), context: &context)
            case .lessThan:
                let signed = nodes[operands[node.operands.lowerBound].rawValue].type.isSigned
                value = try scalar(a.isLessThanFourState(operand(1, &context), signed: signed, context: &context), context: &context)
            case .logicalNot: value = try scalar(a.logicalFourState(context: &context).inverted, context: &context)
            case .logicalAnd: value = try scalar(a.logicalFourState(context: &context).and(operand(1, &context).logicalFourState(context: &context)), context: &context)
            case .logicalOr: value = try scalar(a.logicalFourState(context: &context).or(operand(1, &context).logicalFourState(context: &context)), context: &context)
            case .reduceAnd: value = try scalar(a.reducingFourState(.and, context: &context), context: &context)
            case .reduceOr: value = try scalar(a.reducingFourState(.or, context: &context), context: &context)
            case .reduceXor: value = try scalar(a.reducingFourState(.xor, context: &context), context: &context)
            case .shiftLeft: value = try a.shiftingFourState(left: true, amount: operand(1, &context), context: &context)
            case .shiftRight(let arithmetic): value = try a.shiftingFourState(left: false, amount: operand(1, &context), arithmetic: arithmetic, context: &context)
            case .select: value = try a.selectingFourState(ifTrue: operand(1, &context), ifFalse: operand(2, &context), context: &context)
            case .slice(let offset): value = try a.slicingFourState(offset: offset, width: node.type.width, context: &context)
            case .concatenate:
                var result = try operand(node.operands.count - 1, &context)
                if node.operands.count > 1 {
                    for position in stride(from: node.operands.count - 2, through: 0, by: -1) {
                        result = try operand(position, &context).concatenatingFourState(result, context: &context)
                    }
                }
                value = result
            }
        }
        return value
    }
    private static func scalar(_ bit: LogicBit, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        try .init(repeating: bit, width: .init(1), context: &context)
    }
    private static func boundedOffset(_ value: borrowing LogicFourStateVector, signed: Bool, upperBound: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int? {
        if signed, try value.bit(at: value.width.value - 1) != .zero { return nil }
        var result = 0
        for bit in 0..<value.width.value {
            try context.charge(.workUnits)
            let digit = try value.bit(at: bit)
            guard digit.isKnown else { return nil }
            if digit == .one {
                guard bit < Int.bitWidth - 1 else { return nil }
                result |= 1 << bit
                if result >= upperBound { return nil }
            }
        }
        return result
    }
}
