import LogicIR

internal enum OptimizationKey: Hashable {
    case input(Int), state(Int), constant(Bool), invert(Int)
    case and(Int, Int), or(Int, Int), xor(Int, Int), select(Int, Int, Int)
    var operandCount: Int {
        switch self {
        case .input, .state, .constant: 0
        case .invert: 1
        case .and, .or, .xor: 2
        case .select: 3
        }
    }
    func operand(_ index: Int) -> Int {
        switch self {
        case .invert(let a): a
        case .and(let a, let b), .or(let a, let b), .xor(let a, let b): index == 0 ? a : b
        case .select(let a, let b, let c): index == 0 ? a : index == 1 ? b : c
        case .input, .state, .constant: preconditionFailure("Leaf has no operand")
        }
    }
    var operation: BitOperation {
        switch self {
        case .input: .input
        case .state(let s): .state(.init(s))
        case .constant(let v): .constant(v)
        case .invert: .invert
        case .and: .and
        case .or: .or
        case .xor: .xor
        case .select: .select
        }
    }
}
