import LogicIR
import LogicKernelCore

public struct NativeLogicTechnologyMapper: LogicTechnologyMapping {
    public init() {}
    public func map(_ design: borrowing BitLogicDesign, library: borrowing LogicTechnologyLibrary,
                    policy: borrowing LogicMappingPolicy, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicMappingCandidate {
        try context.checkpoint()
        var maximumPins = 0; var maximumFunction = 0
        for ci in 0..<library.cellCount {
            try context.charge(.workUnits); let cell = try library.cell(at: .init(ci))
            maximumPins = max(maximumPins, cell.pinCount)
            for pi in 0..<cell.pinCount {
                try context.charge(.workUnits)
                if let function = try cell.pin(at: .init(pi)).function { maximumFunction = max(maximumFunction, function.nodeCount) }
            }
            if let state = cell.state { maximumFunction = max(maximumFunction, state.nextState.nodeCount) }
        }
        let n = try MappingArithmetic.sum(MappingArithmetic.product(design.nodeCount, 8), MappingArithmetic.product(design.stateCount, 15))
        let instanceCapacity = try MappingArithmetic.sum(MappingArithmetic.product(n, 4), design.stateCount)
        let netCapacity = try MappingArithmetic.sum(MappingArithmetic.product(instanceCapacity, maximumPins), MappingArithmetic.sum(n, 2))
        let cutCount = try MappingArithmetic.product(n, MappingArithmetic.sum(policy.maximumCutsPerNode, 1))
        let pinStride = try MappingArithmetic.product(maximumPins, MemoryLayout<Int>.stride)
        let slots = try MappingArithmetic.sum(maximumPins, 1)
        var bytes = 0
        for (count, stride) in [(cutCount, MemoryLayout<MappingCut>.stride + 6 * MemoryLayout<Int>.stride),
            (n, MemoryLayout<MappingSolution?>.stride + MemoryLayout<[MappingCut]>.stride + 8 * MemoryLayout<Int>.stride),
            (instanceCapacity, try MappingArithmetic.sum(MemoryLayout<MappingInstanceDraft>.stride + 4 * MemoryLayout<UInt64>.stride, pinStride)),
            (netCapacity, MemoryLayout<MappedGateNet>.stride + 4 * MemoryLayout<Int>.stride),
            (n, try MappingArithmetic.sum(MemoryLayout<MappingMatch>.stride, MappingArithmetic.product(slots, MemoryLayout<Int>.stride))),
            (design.stateCount, try MappingArithmetic.sum(MemoryLayout<MappingMatch>.stride, MappingArithmetic.product(slots, MemoryLayout<Int>.stride))),
            (maximumFunction, MemoryLayout<UInt64>.stride + MemoryLayout<Bool>.stride),
            (slots, 12 * MemoryLayout<Int>.stride),
            (design.portBitCount, 2 * MemoryLayout<MappedNetIndex>.stride),
            (cutCount, MemoryLayout<MappingCut>.stride + 6 * MemoryLayout<Int>.stride),
            (n, MemoryLayout<MappingLogicDraft>.stride + 12 * MemoryLayout<Int>.stride),
            (design.stateCount, MemoryLayout<BitLogicState>.stride + 2 * MemoryLayout<Int>.stride),
            (design.portCount, MemoryLayout<BitLogicPort>.stride + 4 * MemoryLayout<UInt64>.stride),
            (design.stateCount, 4 * MemoryLayout<UInt64>.stride)] {
            bytes = try MappingArithmetic.sum(bytes, MappingArithmetic.product(count, stride))
        }
        bytes = try MappingArithmetic.sum(bytes, MappingArithmetic.product(2, MemoryLayout<MappingMatch?>.stride))
        if case .physicalCells = policy.realizationPolicy {
            bytes = try MappingArithmetic.sum(bytes, MappingArithmetic.product(2, pinStride))
        }
        let receipt = try context.reserveStorage(byteCount: UInt64(bytes))
        let result: LogicMappingCandidate
        do throws(LogicKernelError) {
            let normalized = try MappingControlExpansion.expand(design, policy: policy, context: &context)
            var matcher = MappingFunctionMatcher(library: library, maximumInputs: policy.maximumCellInputs,
                functionCapacity: maximumFunction, pinCapacity: slots)
            let inverter = try matcher.combinational(truth: 1, count: 1, inverter: nil, context: &context)
            var ties: [MappingMatch?] = [nil, nil]
            if case .physicalCells = policy.realizationPolicy {
                for value in 0..<2 { ties[value] = try matcher.constant(value == 1, context: &context) }
            }
            var cover = MappingCoverWorkspace(nodeCount: normalized.nodeCount, policy: policy)
            try cover.build(normalized, matcher: &matcher, inverter: inverter, context: &context)
            var netlist = MappingNetlistWorkspace(graph: normalized, library: library, policy: policy,
                inverter: inverter, tieMatches: ties, netCapacity: netCapacity, instanceCapacity: instanceCapacity)
            let mapped = try netlist.build(normalized, cover: cover, matcher: &matcher, context: &context)
            try NativeMappedGateRealizationValidator().validate(mapped, policy: policy.realizationPolicy, context: &context)
            let metrics = try MappingMetrics.measure(mapped, matcher: &matcher, context: &context)
            _ = try context.reserveStorage(byteCount: UInt64(try MappingArithmetic.sum(
                MappingArithmetic.product(design.nodeCount, MemoryLayout<LogicMappingOrigin>.stride),
                MemoryLayout<(BitLogicDesign, MappedGateDesign, LogicMappingStatistics, [LogicMappingOrigin])>.stride)))
            var outputBytes = try MappingArithmetic.sum(
                MappingArithmetic.product(mapped.netCount, MemoryLayout<MappedGateNet>.stride),
                MappingArithmetic.product(mapped.instanceCount, MemoryLayout<MappedGateInstance>.stride))
            outputBytes = try MappingArithmetic.sum(outputBytes, MappingArithmetic.product(mapped.pinConnectionCount, MemoryLayout<MappedNetIndex>.stride))
            outputBytes = try MappingArithmetic.sum(outputBytes, MappingArithmetic.product(mapped.portCount, MemoryLayout<MappedGatePort>.stride))
            outputBytes = try MappingArithmetic.sum(outputBytes, MappingArithmetic.product(mapped.portBitCount, MemoryLayout<MappedNetIndex>.stride))
            outputBytes = try MappingArithmetic.sum(outputBytes, MappingArithmetic.product(design.nodeCount, MemoryLayout<LogicMappingOrigin>.stride))
            try context.charge(.outputBytes, amount: UInt64(outputBytes))
            var origins: [LogicMappingOrigin] = []; origins.reserveCapacity(design.nodeCount)
            for i in 0..<design.nodeCount {
                try context.charge(.workUnits); let net = netlist.mapped[i]
                origins.append(.init(source: .init(i), net: net < 0 ? nil : .init(net)))
            }
            result = .init(source: copy design, design: mapped, statistics: metrics, origins: origins)
        } catch { try context.releaseStorage(receipt); throw error }
        try context.releaseStorage(receipt); return result
    }
}
