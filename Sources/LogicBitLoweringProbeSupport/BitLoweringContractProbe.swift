import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicLowering

public enum BitLoweringContractProbe {
    @available(macOS 26.0, *)
    public nonisolated static func exercise() throws(LogicKernelError) {
        let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(10_000_000)) }))
        let cancellation = LogicCancellationSource()
        var context = LogicKernelContext(limits: limits, control: cancellation)
        let wide = WordLogicType(width: try LogicBitWidth(9), isSigned: true)
        let boolean = WordLogicType(width: try LogicBitWidth(1))
        let amountType = WordLogicType(width: try LogicBitWidth(129))
        var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 9, operands: 4, ports: 9, states: 1), context: &context)
        let types = [wide, wide, amountType, boolean, boolean, boolean]
        for index in types.indices {
            let input = try builder.addNode(id: entity(index), type: types[index], operation: .input, context: &context)
            try builder.addPort(WordLogicPort(id: entity(index + 100), direction: .input, value: input), context: &context)
        }
        let sum = try builder.addNode(id: entity(6), type: wide, operation: .compute(.add),
                                      inputs: [WordNodeIndex(0), WordNodeIndex(1)], context: &context)
        let shift = try builder.addNode(id: entity(7), type: wide, operation: .compute(.shiftRight(arithmetic: true)),
                                        inputs: [sum, WordNodeIndex(2)], context: &context)
        let q = try builder.addNode(id: entity(8), type: wide, operation: .state(WordStateIndex(0)), context: &context)
        let reset = WordReset(signal: WordNodeIndex(5), activeHigh: false,
            value: try LogicFourStateVector(width: wide.width, valueWords: [341], unknownWords: [0]), kind: .asynchronous)
        _ = try builder.addState(WordLogicState(id: entity(200), next: sum,
            control: .flipFlop(clock: WordNodeIndex(3), edge: .falling, enable: WordNodeIndex(4), reset: reset)), context: &context)
        for (index, word) in [sum, shift, q].enumerated() {
            try builder.addPort(WordLogicPort(id: entity(300 + index), direction: .output, value: word), context: &context)
        }
        let word = try builder.finish(context: &context)
        let kernel: any LogicBitLowering = NativeLogicBitLowering()
        let bit = try kernel.lower(word, context: &context)
        let correct = bit.withTables { nodes, operands, ports, portBits, states, order in
            var values = [Bool](repeating: false, count: nodes.count)
            // 255 + 1 is the signed nine-bit value -256; a 129-bit shift saturates.
            for index in 0..<8 { values[portBits[ports[0].bits.lowerBound + index].rawValue] = true }
            values[portBits[ports[1].bits.lowerBound].rawValue] = true
            values[portBits[ports[2].bits.lowerBound + 128].rawValue] = true
            for ordinal in order.indices {
                let index = order[ordinal].rawValue; let node = nodes[index]
                func input(_ offset: Int) -> Bool { values[operands[node.operands.lowerBound + offset].rawValue] }
                switch node.operation {
                case .input, .state: break
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
            for index in 0..<9 {
                guard values[portBits[ports[6].bits.lowerBound + index].rawValue] == (index == 8),
                      values[portBits[ports[7].bits.lowerBound + index].rawValue],
                      states[index].next == portBits[ports[6].bits.lowerBound + index],
                      states[index].initialValue == nil else { return false }
                guard case .flipFlop(let clock, .falling, let enable, let reset) = states[index].control,
                      clock == portBits[ports[3].bits.lowerBound], enable == portBits[ports[4].bits.lowerBound],
                      let reset, reset.signal == portBits[ports[5].bits.lowerBound], !reset.activeHigh,
                      reset.kind == .asynchronous, reset.value == ((341 >> index) & 1 != 0) else { return false }
            }
            return true
        }
        guard correct else { throw .invalidModel("Bit arithmetic/state probe disagrees") }
        cancellation.cancel()
        do throws(LogicKernelError) {
            _ = try kernel.lower(word, context: &context)
            throw .invalidModel("Cancelled lowering returned a design")
        } catch { guard error == .cancelled else { throw error } }
        var tinyLimits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        tinyLimits[.managedStorageBytes] = 1
        var tiny = LogicKernelContext(limits: try LogicKernelLimits(maximums: tinyLimits), control: LogicCancellationSource())
        do throws(LogicKernelError) {
            _ = try kernel.lower(word, context: &tiny)
            throw .invalidModel("Storage-limited lowering returned a design")
        } catch {
            guard case .resourceLimit(resource: .managedStorageBytes, limit: 1, requested: _) = error else { throw error }
        }
    }

    private nonisolated static func entity(_ index: Int) throws(LogicKernelError) -> DesignEntityID {
        do { return try DesignEntityID(rawValue: UInt64(index + 1)) }
        catch { throw .invalidModel("Probe entity identity is invalid") }
    }
}
