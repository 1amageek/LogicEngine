import LogicIR
import LogicKernelCore

internal final class RTLSimulationPlan: Sendable {
    let design: ElaboratedRTL
    let offsets: [Int]
    let reads: [Bool]
    let writes: [Bool]
    let blockingFF: [Bool]
    let stateCount: Int
    let statementStackCapacity: Int
    var bitCount: Int { offsets.last ?? 0 }
    init(design: ElaboratedRTL, offsets: consuming [Int], reads: consuming [Bool], writes: consuming [Bool],
         blockingFF: consuming [Bool], stateCount: Int, statementStackCapacity: Int) {
        self.design = design; self.offsets = offsets; self.reads = reads; self.writes = writes
        self.blockingFF = blockingFF; self.stateCount = stateCount; self.statementStackCapacity = statementStackCapacity
    }
    static let payloadByteCount = UInt64(MemoryLayout<(ElaboratedRTL, [Int], [Bool], [Bool], [Bool], Int, Int)>.stride)
    static func admitSource(_ design: borrowing ElaboratedRTL, context: inout LogicKernelContext) throws(LogicKernelError) {
        let count = UInt64(design.expressionCount).addingReportingOverflow(UInt64(design.statementCount))
        let total = count.partialValue.addingReportingOverflow(UInt64(design.signalCount))
        guard !count.overflow, !total.overflow else { throw .invalidInput("RTL model node count overflows") }
        try context.require(.nodes, amount: total.partialValue)
        try design.withProgram { signals, _, _, _, _, _, _ throws(LogicKernelError) in
            for index in signals.indices { try context.observeBitWidth(UInt64(signals[index].type.width.value)) }
        }
    }
    func admit(context: inout LogicKernelContext) throws(LogicKernelError) {
        try Self.admitSource(design, context: &context)
        try context.require(.states, amount: UInt64(stateCount))
    }
}
