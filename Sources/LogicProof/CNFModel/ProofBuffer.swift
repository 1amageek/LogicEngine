import LogicKernelCore

internal struct ProofBuffer<Element>: ~Copyable {
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
            guard !next.1 else { throw .invalidInput("Search buffer capacity overflows") }
            let bytes = UInt64(next.0).multipliedReportingOverflow(by: UInt64(MemoryLayout<Element>.stride))
            guard !bytes.overflow else { throw .invalidInput("Search buffer payload overflows") }
            let replacement = try context.reserveStorage(byteCount: bytes.partialValue)
            elements.reserveCapacity(next.0)
            let previous = receipt.take()
            receipt = consume replacement; capacity = next.0
            if let previous { try context.releaseStorage(previous) }
        }
        elements.append(value)
    }
    borrowing func withSlice<Result, Failure: Error>(_ range: Range<Int>, _ body: (borrowing Span<Element>) throws(Failure) -> Result) throws(Failure) -> Result {
        try body(elements.span.extracting(range))
    }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        elements = []; capacity = 0
        let previous = receipt.take()
        if let previous { try context.releaseStorage(previous) }
    }
}
