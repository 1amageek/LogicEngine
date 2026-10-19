import LogicKernelCore

internal struct RTLAdmissionBuffer<Element>: ~Copyable {
    private var elements: [Element] = []
    private var capacity = 0
    private var receipt: LogicStorageReservation?
    var count: Int { elements.count }
    var indices: Range<Int> { elements.indices }
    subscript(index: Int) -> Element {
        _read { yield elements[index] }
        _modify { yield &elements[index] }
    }
    mutating func append(_ value: consuming Element, context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.charge(.workUnits)
        if elements.count == capacity {
            let next = capacity == 0 ? (1, false) : capacity.multipliedReportingOverflow(by: 2)
            guard !next.1 else { throw .invalidInput("RTL admission buffer capacity overflows") }
            let bytes = UInt64(next.0).multipliedReportingOverflow(by: UInt64(MemoryLayout<Element>.stride))
            guard !bytes.overflow else { throw .invalidInput("RTL admission buffer payload overflows") }
            let replacement = try context.reserveStorage(byteCount: bytes.partialValue)
            elements.reserveCapacity(next.0)
            let previous = receipt.take()
            receipt = consume replacement; capacity = next.0
            if let previous { try context.releaseStorage(previous) }
        }
        elements.append(value)
    }
    mutating func popLast() -> Element? { elements.popLast() }
    mutating func truncate(_ count: Int) { elements.removeLast(elements.count - count) }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        elements = []; capacity = 0
        let previous = receipt.take()
        receipt = nil
        if let previous { try context.releaseStorage(previous) }
    }
}
