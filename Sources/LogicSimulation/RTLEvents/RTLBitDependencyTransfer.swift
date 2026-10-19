import LogicIR
import LogicKernelCore

internal enum RTLBitDependencyTransfer {
    static func visit(_ expression: Int, bit: Int, expressions: borrowing Span<RTLResolvedExpression>,
                      operands: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext,
                      _ body: (Int, Int, inout LogicKernelContext) throws(LogicKernelError) -> Void) throws(LogicKernelError) {
        let node = expressions[expression]
        func operand(_ position: Int) -> Int { operands[node.operands.lowerBound + position].rawValue }
        func all(_ source: Int) throws(LogicKernelError) {
            for index in 0..<expressions[source].type.width.value { try body(source, index, &context) }
        }
        switch node.operation {
        case .read, .constant: break
        case .caseEqual: try all(operand(0)); try all(operand(1))
        case .dynamicSelect: try all(operand(0)); try all(operand(1))
        case .compute(let opcode):
            let first = operand(0)
            switch opcode {
            case .bitcast, .invert: try body(first, bit, &context)
            case .zeroExtend: if bit < expressions[first].type.width.value { try body(first, bit, &context) }
            case .signExtend: try body(first, min(bit, expressions[first].type.width.value - 1), &context)
            case .slice(let offset): try body(first, bit + offset, &context)
            case .concatenate:
                var offset = 0
                for position in node.operands.reversed() {
                    try context.charge(.workUnits)
                    let source = operands[position].rawValue; let width = expressions[source].type.width.value
                    if bit >= offset && bit - offset < width { try body(source, bit - offset, &context); break }
                    offset += width
                }
            case .and, .or, .xor: try body(first, bit, &context); try body(operand(1), bit, &context)
            case .add, .subtract, .multiply, .negate:
                // Word arithmetic propagates any unknown operand bit to every
                // result bit; binary carry-only demand would miss this dependency.
                for position in node.operands { try all(operands[position].rawValue) }
            case .select:
                try all(first); try body(operand(1), bit, &context); try body(operand(2), bit, &context)
            case .equal, .lessThan, .logicalNot, .logicalAnd, .logicalOr, .reduceAnd, .reduceOr, .reduceXor,
                 .shiftLeft, .shiftRight:
                for position in node.operands { try all(operands[position].rawValue) }
            }
        }
    }
}
