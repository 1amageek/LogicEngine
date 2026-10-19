import LogicSimulation
import LogicKernelCore

internal struct SymbolicRelation: ~Copyable {
    struct Action {
        let kind: LogicBinaryStateAction.Kind
        let control: LogicSATLiteral
        let sampled: LogicSATLiteral
        let asynchronous: LogicSATLiteral
    }
    var outputs: [LogicSATLiteral]
    var actions: [Action]
    var receipt: LogicStorageReservation?
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        outputs = []; actions = []
        let reservation = receipt.take(); if let reservation { try context.releaseStorage(reservation) }
    }
}
