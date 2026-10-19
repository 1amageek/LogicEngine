import LogicIR
import LogicKernelCore

internal enum MappingMetrics {
    static func measure(_ graph: borrowing MappedGateDesign, matcher: inout MappingFunctionMatcher,
                        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicMappingStatistics {
        let reservation = try context.reserveStorage(byteCount: UInt64(try MappingArithmetic.product(graph.netCount, MemoryLayout<Int>.stride)))
        let result: LogicMappingStatistics
        do throws(LogicKernelError) {
            result = try graph.withTables { nets, instances, pins, _, _, order throws(LogicKernelError) in
                var depths = [Int](repeating: 0, count: nets.count); var area: Double = 0; var maximum = 0
                for i in instances.indices { try context.charge(.workUnits); area += try graph.library.cell(at: instances[i].cell).area }
                guard area.isFinite else { throw .invalidModel("Actual mapped area overflows") }
                for i in order.indices {
                    try context.charge(.workUnits)
                    guard case .net(let ni) = order[i], case .instanceOutput(let ii, let pi) = nets[ni.rawValue].driver else { continue }
                    let instance = instances[ii.rawValue]; let cell = try graph.library.cell(at: instance.cell)
                    guard let function = try cell.pin(at: pi).function else { throw .invalidModel("Mapped output lost its function") }
                    let support = try matcher.supportOf(function, context: &context)
                    var depth = 0; var combinational = cell.state == nil
                    for slot in support where slot < cell.pinCount {
                        try context.charge(.workUnits); combinational = true
                        depth = max(depth, depths[pins[instance.pins.lowerBound + slot].rawValue])
                    }
                    depths[ni.rawValue] = try MappingArithmetic.sum(depth, combinational ? 1 : 0)
                    maximum = max(maximum, depths[ni.rawValue])
                }
                return .init(instanceCount: instances.count, area: area, combinationalDepth: maximum)
            }
        } catch { try context.releaseStorage(reservation); throw error }
        try context.releaseStorage(reservation); return result
    }
}
