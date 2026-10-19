import LogicKernelCore

// This internal helper is only used by the exclusive procedural workspace.
internal struct ProceduralBuffer<Element> {
    private(set) var values: [Element] = []
    private var capacity = 0
    var count: Int { values.count }
    var indices: Range<Int> { values.indices }
    subscript(index: Int) -> Element {
        get { values[index] }
        _modify { yield &values[index] }
    }
    mutating func append(_ value: Element, receipt: inout LogicStorageReservation, bytes: inout UInt64,
                         context: inout LogicKernelContext) throws(LogicKernelError) {
        let next = count.addingReportingOverflow(1)
        guard !next.overflow else {
            throw .resourceLimit(resource: .managedStorageBytes, limit: context.limits[.managedStorageBytes], requested: nil)
        }
        try reserve(next.partialValue, receipt: &receipt, bytes: &bytes, context: &context)
        values.append(value)
    }
    mutating func popLast() -> Element? { values.popLast() }
    mutating func truncate(_ count: Int) { values.removeLast(values.count - count) }
    mutating func reserve(_ required: Int,
                              receipt: inout LogicStorageReservation, bytes: inout UInt64,
                              context: inout LogicKernelContext) throws(LogicKernelError) {
        guard required > capacity else { return }
        let doubled = capacity.multipliedReportingOverflow(by: 2)
        let next = max(required, doubled.overflow ? required : max(4, doubled.partialValue))
        let delta = UInt64(next - capacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<Element>.stride))
        let total = bytes.addingReportingOverflow(delta.partialValue)
        guard !delta.overflow, !total.overflow else {
            throw .resourceLimit(resource: .managedStorageBytes, limit: context.limits[.managedStorageBytes], requested: nil)
        }
        // Budget the complete replacement footprint while the old footprint is live.
        // Unchanged arrays are conservatively counted twice during this admission.
        let replacement = try context.reserveStorage(byteCount: total.partialValue)
        values.reserveCapacity(next)
        let previous = consume receipt
        receipt = replacement
        bytes = total.partialValue; capacity = next
        try context.releaseStorage(previous)
    }
}
