import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func constantCompute(_ opcode: WordLogicOpcode, type: WordLogicType, a: Int, b: Int,
                                  origin: LogicKernelSourceRange?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int? {
        guard case .constant(let left) = nodes[a].operation else { return nil }
        let right: LogicFourStateVector?
        if b >= 0 {
            guard case .constant(let value) = nodes[b].operation else { return nil }
            right = value
        } else { right = nil }
        let vector: LogicFourStateVector
        switch opcode {
        case .bitcast: vector = left
        case .zeroExtend: vector = try left.resizedBinary(to: type.width, signExtend: false, context: &context)
        case .signExtend: vector = try left.resizedBinary(to: type.width, signExtend: true, context: &context)
        case .invert: vector = try left.invertingBinary(context: &context)
        case .negate: vector = try left.negatingBinary(context: &context)
        case .and: vector = try left.applyingBinary(.and, to: right!, context: &context)
        case .or: vector = try left.applyingBinary(.or, to: right!, context: &context)
        case .xor: vector = try left.applyingBinary(.xor, to: right!, context: &context)
        case .add: vector = try left.addingBinary(right!, context: &context)
        case .subtract: vector = try left.subtractingBinary(right!, context: &context)
        case .multiply: vector = try left.multiplyingBinary(right!, context: &context)
        case .equal: return try left.equalsBinary(right!, context: &context) ? 1 : 0
        case .lessThan: return try left.isLessThanBinary(right!, signed: nodes[a].type.isSigned, context: &context) ? 1 : 0
        case .logicalNot: return try left.reducingBinary(.or, context: &context) ? 0 : 1
        case .logicalAnd, .logicalOr:
            let av = try left.reducingBinary(.or, context: &context)
            let bv = try right!.reducingBinary(.or, context: &context)
            return (opcode == .logicalAnd ? av && bv : av || bv) ? 1 : 0
        case .reduceAnd: return try left.reducingBinary(.and, context: &context) ? 1 : 0
        case .reduceOr: return try left.reducingBinary(.or, context: &context) ? 1 : 0
        case .reduceXor: return try left.reducingBinary(.xor, context: &context) ? 1 : 0
        case .shiftLeft: vector = try left.shiftingBinary(left: true, amount: right!, context: &context)
        case .shiftRight(let arithmetic):
            vector = try left.shiftingBinary(left: false, amount: right!, arithmetic: arithmetic && nodes[a].type.isSigned, context: &context)
        case .slice(let offset): vector = try left.slicingBinary(offset: offset, width: type.width, context: &context)
        case .select, .concatenate: return nil
        }
        if type == scalar { return try vector.bit(at: 0) == .one ? 1 : 0 }
        return try emit(type: type, operation: .constant(vector), origin: origin, context: &context)
    }
}
