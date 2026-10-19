import LogicKernelCore
import LogicSimulation

internal struct EquivalenceMiter: ~Copyable {
    let formula: LogicCNFFormula
    var inputVariables: [LogicSATLiteral]
    var stateVariables: [LogicSATLiteral]
    private var receipt: LogicStorageReservation?
    private init(formula: LogicCNFFormula, inputs: consuming [LogicSATLiteral], states: consuming [LogicSATLiteral], receipt: consuming LogicStorageReservation) {
        self.formula = formula; inputVariables = inputs; stateVariables = states; self.receipt = consume receipt
    }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        inputVariables = []; stateVariables = []
        let reservation = receipt.take(); if let reservation { try context.releaseStorage(reservation) }
    }
    static func build(_ problem: borrowing LogicEquivalenceProblem, context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        var builder = TseitinBuilder()
        do throws(LogicKernelError) {
            let zero = try builder.constant(false, context: &context)
            let count = UInt64(problem.inputBitCount).addingReportingOverflow(UInt64(problem.stateBitCount))
            let bytes = count.partialValue.multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicSATLiteral>.stride * 4))
            guard !count.overflow, !bytes.overflow else { throw .invalidInput("Miter interface workspace overflows") }
            let reservation = try context.reserveStorage(byteCount: bytes.partialValue)
            do throws(LogicKernelError) {
                var inputs = [LogicSATLiteral](repeating: zero, count: problem.inputBitCount)
                var candidateInputs = inputs
                var states = [LogicSATLiteral](repeating: zero, count: problem.stateBitCount)
                var candidateStates = states
                for pair in problem.storage.inputs {
                    let variable = try builder.fresh(context: &context)
                    inputs[pair.reference] = variable; candidateInputs[pair.candidate] = variable
                }
                for pair in problem.storage.states {
                    let variable = try builder.fresh(context: &context)
                    states[pair.reference] = variable; candidateStates[pair.candidate] = variable
                }
                var lhs = try SymbolicCircuitEncoder.encode(problem.storage.reference, inputs: inputs.span, states: states.span,
                    zero: zero, builder: &builder, context: &context)
                do throws(LogicKernelError) {
                    var rhs = try SymbolicCircuitEncoder.encode(problem.storage.candidate, inputs: candidateInputs.span, states: candidateStates.span,
                        zero: zero, builder: &builder, context: &context)
                    do throws(LogicKernelError) {
                        var difference = zero
                        for pair in problem.storage.outputs {
                            let mismatch = try builder.xor(lhs.outputs[pair.reference], rhs.outputs[pair.candidate], context: &context)
                            difference = try builder.or(difference, mismatch, context: &context)
                        }
                        for pair in problem.storage.states {
                            let left = lhs.actions[pair.reference]; let right = rhs.actions[pair.candidate]
                            let leftControl = problem.storage.referenceShape.controlInversions[pair.reference] ? left.control.negated : left.control
                            let rightControl = problem.storage.candidateShape.controlInversions[pair.candidate] ? right.control.negated : right.control
                            let control = try builder.xor(leftControl, rightControl, context: &context)
                            difference = try builder.or(difference, control, context: &context)
                            let asynchronous = try builder.xor(left.asynchronous, right.asynchronous, context: &context)
                            difference = try builder.or(difference, asynchronous, context: &context)
                            let leftEvent: LogicSATLiteral; let rightEvent: LogicSATLiteral
                            switch problem.storage.referenceShape.kinds[pair.reference] {
                            case .latch: leftEvent = left.sampled; rightEvent = right.sampled
                            case .flipFlop(let rising):
                                leftEvent = try builder.select(rising ? leftControl : leftControl.negated, left.sampled, left.asynchronous, context: &context)
                                rightEvent = try builder.select(rising ? rightControl : rightControl.negated, right.sampled, right.asynchronous, context: &context)
                            }
                            let update = try builder.xor(leftEvent, rightEvent, context: &context)
                            difference = try builder.or(difference, update, context: &context)
                        }
                        try builder.clause(difference, context: &context)
                        let formula = try builder.finish(context: &context)
                        try rhs.release(context: &context)
                        try lhs.release(context: &context)
                        try builder.release(context: &context)
                        return .init(formula: formula, inputs: inputs, states: states, receipt: reservation)
                    } catch { try rhs.release(context: &context); throw error }
                } catch { try lhs.release(context: &context); throw error }
            } catch { try context.releaseStorage(reservation); throw error }
        } catch { try builder.release(context: &context); throw error }
    }
}
