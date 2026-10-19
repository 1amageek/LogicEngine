import LogicIR
import LogicKernelCore

extension NativeLogicTechnologyMapper: LogicMappedDesignMeasuring {
    public func measure(_ design: borrowing MappedGateDesign, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicMappingStatistics {
        var pins = 0; var functions = 0
        for c in 0..<design.library.cellCount {
            try context.charge(.workUnits)
            let cell = try design.library.cell(at: .init(c)); pins = max(pins, cell.pinCount)
            for p in 0..<cell.pinCount {
                if let function = try cell.pin(at: .init(p)).function { functions = max(functions, function.nodeCount) }
            }
        }
        let slots = try MappingArithmetic.sum(pins, 1)
        let bytes = try MappingArithmetic.sum(MappingArithmetic.product(functions, MemoryLayout<UInt64>.stride + MemoryLayout<Bool>.stride),
                                             MappingArithmetic.product(slots, 3 * MemoryLayout<Int>.stride))
        let reservation = try context.reserveStorage(byteCount: UInt64(bytes))
        let result: LogicMappingStatistics
        do throws(LogicKernelError) {
            var matcher = MappingFunctionMatcher(library: design.library, maximumInputs: 6,
                                                 functionCapacity: functions, pinCapacity: slots)
            result = try MappingMetrics.measure(design, matcher: &matcher, context: &context)
        } catch { try context.releaseStorage(reservation); throw error }
        try context.releaseStorage(reservation); return result
    }
}
