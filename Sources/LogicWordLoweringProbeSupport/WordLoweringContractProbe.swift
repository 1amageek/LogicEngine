import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicLowering

public enum WordLoweringContractProbe {
    private static func entity(_ ordinal: Int) throws(LogicKernelError) -> DesignEntityID {
        do { return try DesignEntityID(rawValue: UInt64(ordinal) + 1) }
        catch { throw .invalidModel("Invalid probe entity") }
    }

    @available(macOS 26.0, *)
    public nonisolated static func exercise() throws(LogicKernelError) {
        let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(10_000_000)) }))
        let cancellation = LogicCancellationSource()
        var source = LogicKernelContext(limits: limits, control: cancellation)
        let wide = WordLogicType(width: try LogicBitWidth(9)); let scalar = WordLogicType(width: try LogicBitWidth(1))
        var builder = try ElaboratedRTLBuilder(topModuleID: entity(0), capacity: RTLResolvedCapacity(
            signals: 5, expressions: 7, operands: 1, statements: 6, children: 2,
            caseItems: 0, caseMatches: 0, ports: 5, processes: 1), context: &source)
        for index in 0..<4 {
            let type = index == 0 ? wide : scalar
            let signal = try builder.addSignal(RTLResolvedSignal(id: entity(index), type: type, isInput: true), context: &source)
            _ = try builder.addExpression(id: entity(index), type: type, operation: .read(signal), context: &source)
            try builder.addPort(RTLResolvedPort(id: entity(index + 100), name: "input\(index)", direction: .input,
                signal: signal), context: &source)
        }
        let q = try builder.addSignal(RTLResolvedSignal(id: entity(4), type: wide), context: &source)
        let five = try builder.addExpression(id: entity(4), type: wide,
            operation: .constant(LogicFourStateVector(width: wide.width, valueWords: [5], unknownWords: [0])), context: &source)
        let two = try builder.addExpression(id: entity(5), type: wide,
            operation: .constant(LogicFourStateVector(width: wide.width, valueWords: [2], unknownWords: [0])), context: &source)
        let asserted = try builder.addExpression(id: entity(6), type: scalar, operation: .compute(.logicalNot),
            inputs: [RTLExpressionIndex(3)], context: &source)
        let reset = try builder.addStatement(RTLResolvedStatement(id: entity(0), operation: .assignment(
            target: q, selection: 0..<9, value: five, timing: .nonBlocking)), context: &source)
        let schedule = try builder.addStatement(RTLResolvedStatement(id: entity(1), operation: .assignment(
            target: q, selection: 0..<9, value: RTLExpressionIndex(0), timing: .nonBlocking)), context: &source)
        let blocking = try builder.addStatement(RTLResolvedStatement(id: entity(2), operation: .assignment(
            target: q, selection: 0..<9, value: two, timing: .blocking)), context: &source)
        let conditional = try builder.addStatement(RTLResolvedStatement(id: entity(3), operation: .conditional(
            condition: RTLExpressionIndex(1), ifTrue: schedule, ifFalse: nil)), context: &source)
        let active = try builder.addBlock(id: entity(4), body: [conditional, blocking], context: &source)
        let body = try builder.addStatement(RTLResolvedStatement(id: entity(5), operation: .conditional(
            condition: asserted, ifTrue: reset, ifFalse: active)), context: &source)
        try builder.addProcess(RTLResolvedProcess(id: entity(0), control: .flipFlop(clock: RTLExpressionIndex(2),
            edge: .falling, asynchronousReset: RTLResolvedReset(signal: RTLExpressionIndex(3), activeHigh: false)),
            body: body), context: &source)
        try builder.addPort(RTLResolvedPort(id: entity(200), name: "q", direction: .output, signal: q), context: &source)
        let rtl = try builder.finish(context: &source)
        var context = LogicKernelContext(limits: limits, control: cancellation)
        let kernel: any LogicWordLowering = NativeLogicWordLowering()
        let word = try kernel.lower(rtl, context: &context)
        let bit = try NativeLogicBitLowering().lower(word, context: &context)
        for enable in [false, true] { for reset in [false, true] {
            let correct = bit.withTables { nodes, operands, ports, bindings, states, order in
                var values = [Bool](repeating: false, count: nodes.count)
                for offset in 0..<9 { values[bindings[ports[0].bits.lowerBound + offset].rawValue] = 303 & (1 << offset) != 0 }
                values[bindings[ports[1].bits.lowerBound].rawValue] = enable
                values[bindings[ports[3].bits.lowerBound].rawValue] = reset
                for ordinal in order.indices {
                    let index = order[ordinal].rawValue; let node = nodes[index]
                    func input(_ offset: Int) -> Bool { values[operands[node.operands.lowerBound + offset].rawValue] }
                    switch node.operation {
                    case .input: break
                    case .state: values[index] = true
                    case .constant(let value): values[index] = value
                    case .buffer: values[index] = input(0)
                    case .invert: values[index] = !input(0)
                    case .and: values[index] = input(0) && input(1)
                    case .or: values[index] = input(0) || input(1)
                    case .xor: values[index] = input(0) != input(1)
                    case .select: values[index] = input(0) ? input(1) : input(2)
                    }
                }
                guard states.count == 9 else { return false }
                let expected = reset ? (enable ? 303 : 2) : 5
                for index in states.indices {
                    guard states[index].initialValue == nil,
                          case .flipFlop(let clock, .falling, nil, let definition?) = states[index].control,
                          clock == bindings[ports[2].bits.lowerBound], definition.kind == .asynchronous,
                          !definition.activeHigh, definition.signal == bindings[ports[3].bits.lowerBound] else { return false }
                    let value = reset ? values[states[index].next.rawValue] : definition.value
                    if value != (expected & (1 << index) != 0) { return false }
                }
                return true
            }
            guard correct else { throw .invalidModel("Procedural lowering changed ordered state semantics") }
        } }
        let inferredRTL = try latchSource(context: &source)
        let inferredWord = try kernel.lower(inferredRTL, context: &context)
        let inferredBit = try NativeLogicBitLowering().lower(inferredWord, context: &context)
        for gate in [false, true] {
            guard checkLatch(inferredBit, gate: gate) else { throw .invalidModel("Inferred latch changed hold/data semantics") }
        }
        cancellation.cancel()
        var cancelled = LogicKernelContext(limits: limits, control: cancellation)
        do throws(LogicKernelError) {
            _ = try kernel.lower(rtl, context: &cancelled)
            throw .invalidModel("Cancellation was ignored")
        } catch { guard error == .cancelled else { throw error } }
        var values = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        values[.managedStorageBytes] = 8
        var bounded = LogicKernelContext(limits: try LogicKernelLimits(maximums: values), control: LogicCancellationSource())
        do throws(LogicKernelError) {
            _ = try kernel.lower(rtl, context: &bounded)
            throw .invalidModel("Storage limit was ignored")
        } catch {
            guard case .resourceLimit(resource: .managedStorageBytes, limit: 8, requested: _) = error else { throw error }
        }
        guard bounded.usage[.managedStorageBytes] == 0 else { throw .invalidModel("Failed lowering leaked workspace accounting") }
    }

    @available(macOS 26.0, *)
    private static func latchSource(context: inout LogicKernelContext) throws(LogicKernelError) -> ElaboratedRTL {
        let wide = WordLogicType(width: try LogicBitWidth(3)); let scalar = WordLogicType(width: try LogicBitWidth(1))
        var builder = try ElaboratedRTLBuilder(topModuleID: entity(0), capacity: RTLResolvedCapacity(
            signals: 4, expressions: 2, operands: 0, statements: 4, children: 2, caseItems: 0,
            caseMatches: 0, ports: 4, processes: 1), context: &context)
        for index in 0..<2 {
            let type = index == 0 ? wide : scalar
            let signal = try builder.addSignal(RTLResolvedSignal(id: entity(index), type: type, isInput: true), context: &context)
            _ = try builder.addExpression(id: entity(index), type: type, operation: .read(signal), context: &context)
            try builder.addPort(RTLResolvedPort(id: entity(index), name: "input\(index)", direction: .input, signal: signal), context: &context)
        }
        let q = try builder.addSignal(RTLResolvedSignal(id: entity(2), type: wide), context: &context)
        let y = try builder.addSignal(RTLResolvedSignal(id: entity(3), type: wide), context: &context)
        let write = try builder.addStatement(RTLResolvedStatement(id: entity(0), operation: .assignment(
            target: q, selection: 0..<3, value: RTLExpressionIndex(0), timing: .blocking)), context: &context)
        let wire = try builder.addStatement(RTLResolvedStatement(id: entity(1), operation: .assignment(
            target: y, selection: 0..<3, value: RTLExpressionIndex(0), timing: .blocking)), context: &context)
        let guarded = try builder.addStatement(RTLResolvedStatement(id: entity(2), operation: .conditional(
            condition: RTLExpressionIndex(1), ifTrue: write, ifFalse: nil)), context: &context)
        let body = try builder.addBlock(id: entity(3), body: [guarded, wire], context: &context)
        try builder.addProcess(RTLResolvedProcess(id: entity(0), control: .levelSensitive, body: body), context: &context)
        try builder.addPort(RTLResolvedPort(id: entity(2), name: "q", direction: .output, signal: q), context: &context)
        try builder.addPort(RTLResolvedPort(id: entity(3), name: "y", direction: .output, signal: y), context: &context)
        return try builder.finish(context: &context)
    }

    @available(macOS 26.0, *)
    private static func checkLatch(_ bit: borrowing BitLogicDesign, gate: Bool) -> Bool {
        bit.withTables { nodes, operands, ports, bindings, states, order in
            var values = [Bool](repeating: false, count: nodes.count)
            for offset in 0..<3 { values[bindings[ports[0].bits.lowerBound + offset].rawValue] = 5 & (1 << offset) != 0 }
            values[bindings[ports[1].bits.lowerBound].rawValue] = gate
            for ordinal in order.indices {
                let index = order[ordinal].rawValue; let node = nodes[index]
                func input(_ offset: Int) -> Bool { values[operands[node.operands.lowerBound + offset].rawValue] }
                switch node.operation {
                case .input: break
                case .state(let state): values[index] = 2 & (1 << state.rawValue) != 0
                case .constant(let value): values[index] = value
                case .buffer: values[index] = input(0)
                case .invert: values[index] = !input(0)
                case .and: values[index] = input(0) && input(1)
                case .or: values[index] = input(0) || input(1)
                case .xor: values[index] = input(0) != input(1)
                case .select: values[index] = input(0) ? input(1) : input(2)
                }
            }
            guard states.count == 3 else { return false }
            for index in states.indices {
                guard case .latch(let control, true, nil) = states[index].control,
                      values[control.rawValue] == gate, states[index].initialValue == nil else { return false }
                let next = gate ? values[states[index].next.rawValue] : 2 & (1 << index) != 0
                if next != ((gate ? 5 : 2) & (1 << index) != 0) { return false }
                if values[bindings[ports[3].bits.lowerBound + index].rawValue] != (5 & (1 << index) != 0) { return false }
            }
            return true
        }
    }
}
