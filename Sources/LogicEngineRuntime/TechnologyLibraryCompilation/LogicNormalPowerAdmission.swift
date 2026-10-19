import LogicKernelCore

/// Conservatively retains source-byte reservations for this invocation, independently of workspace slots.
internal struct LogicNormalPowerAdmission {
    var sourceStorageCredit: UInt64

    mutating func admit(work: UInt64, stateSlots: Int, sourceReservationBytes: UInt64,
                        context: inout LogicKernelContext) throws(LogicKernelError) {
        guard stateSlots >= 0 else { throw .invalidInput("Negative normal-power workspace capacity") }
        try context.charge(.workUnits, amount: work)
        try context.charge(.nodes, amount: UInt64(stateSlots))
        let reused = min(sourceStorageCredit, sourceReservationBytes)
        let additional = sourceReservationBytes - reused
        if additional > 0 { _ = try context.reserveStorage(byteCount: additional) }
        // reserveStorage already charges allocationBytes for the additional portion.
        try context.charge(.allocationBytes, amount: reused)
        sourceStorageCredit -= reused
    }
}
