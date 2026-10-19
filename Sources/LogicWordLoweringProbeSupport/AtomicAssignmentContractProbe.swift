import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicLowering

public enum AtomicAssignmentContractProbe {
    private static func id(_ value: UInt64) throws(LogicKernelError) -> DesignEntityID {
        do { return try DesignEntityID(rawValue: value) }
        catch { throw .invalidModel("Invalid atomic probe identity") }
    }

    @available(macOS 26.0, *)
    public nonisolated static func exercise() throws(LogicKernelError) {
        let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(10_000_000)) }))
        for mode in 0..<3 {
            let cancellation = LogicCancellationSource()
            var context = LogicKernelContext(limits: limits, control: cancellation)
            let rtl = try source(mode: mode, context: &context)
            let kernel: any LogicWordLowering = NativeLogicWordLowering()
            let word = try kernel.lower(rtl, context: &context)
            let bit = try NativeLogicBitLowering().lower(word, context: &context)
            for value in 0..<16 {
                guard check(bit, value: value, sequential: mode == 2) else {
                    throw .invalidModel("Atomic assignment changed sampled swap semantics")
                }
            }
            cancellation.cancel()
            var cancelled = LogicKernelContext(limits: limits, control: cancellation)
            do throws(LogicKernelError) {
                _ = try kernel.lower(rtl, context: &cancelled)
                throw .invalidModel("Atomic assignment ignored cancellation")
            } catch { guard error == .cancelled else { throw error } }
            guard cancelled.usage[.managedStorageBytes] == 0 else {
                throw .invalidModel("Cancelled atomic assignment leaked workspace accounting")
            }
        }
    }

    @available(macOS 26.0, *)
    private static func source(mode: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> ElaboratedRTL {
        let wide = WordLogicType(width: try LogicBitWidth(4))
        let half = WordLogicType(width: try LogicBitWidth(2))
        let scalar = WordLogicType(width: try LogicBitWidth(1))
        var builder = try ElaboratedRTLBuilder(topModuleID: id(1), capacity: RTLResolvedCapacity(
            signals: 3, expressions: 5, operands: 2, statements: 5, children: 4,
            caseItems: 0, caseMatches: 0, ports: 3, processes: 1), context: &context)
        let data = try builder.addSignal(RTLResolvedSignal(id: id(1), type: wide, isInput: true), context: &context)
        let clock = try builder.addSignal(RTLResolvedSignal(id: id(2), type: scalar, isInput: true), context: &context)
        let q = try builder.addSignal(RTLResolvedSignal(id: id(3), type: wide), context: &context)
        let input = try builder.addExpression(id: id(1), type: wide, operation: .read(data), context: &context)
        let edge = try builder.addExpression(id: id(2), type: scalar, operation: .read(clock), context: &context)
        let old = try builder.addExpression(id: id(3), type: wide, operation: .read(q), context: &context)
        let low = try builder.addExpression(id: id(4), type: half, operation: .compute(.slice(offset: 0)),
            inputs: [old], context: &context)
        let high = try builder.addExpression(id: id(5), type: half, operation: .compute(.slice(offset: 2)),
            inputs: [old], context: &context)
        let initial = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .assignment(
            target: q, selection: 0..<4, value: input, timing: .blocking)), context: &context)
        let timing: RTLResolvedStatement.Timing = mode == 0 ? .blocking : .nonBlocking
        let first = try builder.addStatement(RTLResolvedStatement(id: id(2), operation: .assignment(
            target: q, selection: 2..<4, value: low, timing: timing)), context: &context)
        let second = try builder.addStatement(RTLResolvedStatement(id: id(3), operation: .assignment(
            target: q, selection: 0..<2, value: high, timing: timing)), context: &context)
        let group = try builder.addAssignmentGroup(id: id(4), body: [first, second], context: &context)
        let body: RTLStatementIndex
        if mode == 2 { body = group }
        else { body = try builder.addBlock(id: id(5), body: [initial, group], context: &context) }
        try builder.addProcess(RTLResolvedProcess(id: id(1), control: mode == 2
            ? .flipFlop(clock: edge, edge: .rising, asynchronousReset: nil) : .combinational,
            body: body), context: &context)
        try builder.addPort(RTLResolvedPort(id: id(1), name: "data", direction: .input, signal: data), context: &context)
        try builder.addPort(RTLResolvedPort(id: id(2), name: "clock", direction: .input, signal: clock), context: &context)
        try builder.addPort(RTLResolvedPort(id: id(3), name: "q", direction: .output, signal: q), context: &context)
        return try builder.finish(context: &context)
    }

    @available(macOS 26.0, *)
    private static func check(_ bit: borrowing BitLogicDesign, value: Int, sequential: Bool) -> Bool {
        bit.withTables { nodes, operands, ports, bindings, states, order in
            var values = [Bool](repeating: false, count: nodes.count)
            for offset in 0..<4 { values[bindings[ports[0].bits.lowerBound + offset].rawValue] = value & (1 << offset) != 0 }
            for ordinal in order.indices {
                let index = order[ordinal].rawValue; let node = nodes[index]
                func input(_ offset: Int) -> Bool { values[operands[node.operands.lowerBound + offset].rawValue] }
                switch node.operation {
                case .input: break
                case .state(let state): values[index] = value & (1 << state.rawValue) != 0
                case .constant(let constant): values[index] = constant
                case .buffer: values[index] = input(0)
                case .invert: values[index] = !input(0)
                case .and: values[index] = input(0) && input(1)
                case .or: values[index] = input(0) || input(1)
                case .xor: values[index] = input(0) != input(1)
                case .select: values[index] = input(0) ? input(1) : input(2)
                }
            }
            guard states.count == (sequential ? 4 : 0) else { return false }
            let expected = (value << 2 | value >> 2) & 15
            for offset in 0..<4 {
                let actual: Bool
                if sequential {
                    guard case .flipFlop(let clock, .rising, nil, nil) = states[offset].control,
                          clock == bindings[ports[1].bits.lowerBound], states[offset].initialValue == nil else { return false }
                    actual = values[states[offset].next.rawValue]
                } else { actual = values[bindings[ports[2].bits.lowerBound + offset].rawValue] }
                if actual != (expected & (1 << offset) != 0) { return false }
            }
            return true
        }
    }
}
