import LogicIR
import LogicKernelCore

public struct LogicSimulationModel: Sendable {
    internal final class Storage: Sendable {
        private enum Content: Sendable { case mapped(MappedGateDesign, Int), rtl(RTLSimulationPlan) }
        private let content: Content
        static var payloadByteCount: UInt64 { UInt64(MemoryLayout<Content>.stride) }
        init(mapped: MappedGateDesign, scratchCount: Int) { content = .mapped(mapped, scratchCount) }
        init(rtl: RTLSimulationPlan) { content = .rtl(rtl) }
        var mapped: MappedGateDesign? { if case .mapped(let value, _) = content { value } else { nil } }
        var rtl: RTLSimulationPlan? { if case .rtl(let value) = content { value } else { nil } }
        var scratchCount: Int { if case .mapped(_, let count) = content { count } else { 0 } }
        var portCount: Int {
            switch content { case .mapped(let design, _): design.portCount; case .rtl(let plan): plan.design.portCount }
        }
        var stateCount: Int {
            switch content { case .mapped(let design, _): design.stateCount; case .rtl(let plan): plan.stateCount }
        }
        func admit(context: inout LogicKernelContext) throws(LogicKernelError) {
            switch content {
            case .rtl(let plan): try plan.admit(context: &context)
            case .mapped(let mapped, let scratch):
                let nodes = UInt64(mapped.netCount).addingReportingOverflow(UInt64(mapped.instanceCount))
                let edges = UInt64(mapped.pinConnectionCount).addingReportingOverflow(UInt64(mapped.portBitCount))
                guard !nodes.overflow, !edges.overflow else { throw .invalidInput("Simulation model dimensions overflow") }
                try context.require(.nodes, amount: max(nodes.partialValue, UInt64(scratch)))
                try context.require(.edges, amount: edges.partialValue)
                try context.require(.states, amount: UInt64(mapped.stateCount))
                try mapped.withTables { _, _, _, ports, _, _ throws(LogicKernelError) in
                    for index in ports.indices { try context.observeBitWidth(UInt64(ports[index].bits.count)) }
                }
            }
        }
    }
    internal let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var portCount: Int { storage.portCount }
    public var stateCount: Int { storage.stateCount }
}
