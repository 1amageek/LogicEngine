import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicLowering

@Suite(.timeLimit(.minutes(1)))
struct BitExpansionTests {
    private struct Control: LogicRunControlling {
        let failure: LogicKernelError?
        init(_ failure: LogicKernelError? = nil) { self.failure = failure }
        func checkpoint() throws(LogicKernelError) { if let failure { throw failure } }
    }
    private func context(storage: UInt64 = 1_000_000_000, control: Control = Control()) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000_000)) })
        limits[.managedStorageBytes] = storage
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    private func id(_ value: Int) throws -> DesignEntityID { try DesignEntityID(rawValue: UInt64(value)) }
    private func type(_ width: Int, signed: Bool = false) throws -> WordLogicType {
        WordLogicType(width: try LogicBitWidth(width), isSigned: signed)
    }
    private func graph(_ opcode: WordLogicOpcode, inputs: [WordLogicType], output: WordLogicType,
                       origin: LogicKernelSourceRange? = nil, reverseIDs: Bool = false) throws -> WordLogicDesign {
        var context = try context()
        var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: inputs.count + 1,
            operands: inputs.count, ports: inputs.count + 1, states: 0), context: &context)
        // The output is deliberately declared before every operand.
        _ = try builder.addNode(id: id(reverseIDs ? 900 : 1), type: output, operation: .compute(opcode),
            inputs: inputs.indices.map { WordNodeIndex($0 + 1) }, origin: origin, context: &context)
        for index in inputs.indices {
            let word = try builder.addNode(id: id(reverseIDs ? 800 - index : index + 2), type: inputs[index],
                                           operation: .input, origin: origin, context: &context)
            try builder.addPort(WordLogicPort(id: id(100 + index), direction: .input, value: word), context: &context)
        }
        try builder.addPort(WordLogicPort(id: id(200), direction: .output, value: WordNodeIndex(0)), context: &context)
        return try builder.finish(context: &context)
    }
    private func lower(_ graph: borrowing WordLogicDesign) throws -> BitLogicDesign {
        var context = try context()
        let kernel: any LogicBitLowering = NativeLogicBitLowering()
        return try kernel.lower(graph, context: &context)
    }
    // Independent gate interpretation; expected arithmetic below uses native integers.
    private func evaluate(_ graph: borrowing BitLogicDesign, _ inputs: [[Bool]], state: [Bool] = []) throws -> [[Bool]] {
        try graph.withTables { nodes, operands, ports, portBits, states, order in
            var values = [Bool](repeating: false, count: nodes.count)
            var inputIndex = 0
            for port in ports.indices where ports[port].direction == .input {
                let binding = ports[port].bits
                guard inputs.indices.contains(inputIndex), inputs[inputIndex].count == binding.count else {
                    throw LogicKernelError.invalidInput("Reference input binding mismatch")
                }
                for bit in 0..<binding.count { values[portBits[binding.lowerBound + bit].rawValue] = inputs[inputIndex][bit] }
                inputIndex += 1
            }
            for ordinal in order.indices {
                let index = order[ordinal].rawValue; let node = nodes[index]
                func operand(_ offset: Int) -> Bool { values[operands[node.operands.lowerBound + offset].rawValue] }
                switch node.operation {
                case .input: break
                case .constant(let value): values[index] = value
                case .state(let index): values[order[ordinal].rawValue] = state[index.rawValue]
                case .buffer: values[index] = operand(0)
                case .invert: values[index] = !operand(0)
                case .and: values[index] = operand(0) && operand(1)
                case .or: values[index] = operand(0) || operand(1)
                case .xor: values[index] = operand(0) != operand(1)
                case .select: values[index] = operand(0) ? operand(1) : operand(2)
                }
            }
            return ports.indices.filter { ports[$0].direction == .output }.map { port in
                ports[port].bits.map { values[portBits[$0].rawValue] }
            }
        }
    }
    private func bits(_ value: Int, _ width: Int) -> [Bool] { (0..<width).map { (value >> $0) & 1 != 0 } }
    private func integer(_ value: [Bool]) -> Int { value.enumerated().reduce(0) { $0 | ($1.element ? 1 << $1.offset : 0) } }

    @Test func exhaustiveBinaryArithmeticComparisonLogicalAndShifts() throws {
        let operations: [WordLogicOpcode] = [.and, .or, .xor, .add, .subtract, .multiply, .equal, .lessThan,
            .logicalAnd, .logicalOr, .shiftLeft, .shiftRight(arithmetic: false), .shiftRight(arithmetic: true)]
        for width in 1...5 {
            let count = 1 << width; let mask = count - 1
            for signed in [false, true] {
                for operation in operations {
                    let boolean = [.equal, .lessThan, .logicalAnd, .logicalOr].contains(operation)
                    let shift = operation == .shiftLeft || operation == .shiftRight(arithmetic: false) || operation == .shiftRight(arithmetic: true)
                    let word = try graph(operation, inputs: [type(width, signed: signed), type(width, signed: shift ? false : signed)],
                                         output: type(boolean ? 1 : width, signed: boolean ? false : signed))
                    let bit = try lower(word)
                    for a in 0..<count {
                        for b in 0..<count {
                            let sa = signed && a & (count >> 1) != 0 ? a - count : a
                            let sb = signed && b & (count >> 1) != 0 ? b - count : b
                            let expected: Int
                            switch operation {
                            case .and: expected = a & b
                            case .or: expected = a | b
                            case .xor: expected = a ^ b
                            case .add: expected = (a + b) & mask
                            case .subtract: expected = (a - b) & mask
                            case .multiply: expected = (a * b) & mask
                            case .equal: expected = a == b ? 1 : 0
                            case .lessThan: expected = sa < sb ? 1 : 0
                            case .logicalAnd: expected = a != 0 && b != 0 ? 1 : 0
                            case .logicalOr: expected = a != 0 || b != 0 ? 1 : 0
                            case .shiftLeft: expected = b >= width ? 0 : (a << b) & mask
                            case .shiftRight(arithmetic: false): expected = b >= width ? 0 : a >> b
                            case .shiftRight(arithmetic: true): expected = (sa >> min(b, width)) & mask
                            default: throw LogicKernelError.invalidModel("Unexpected reference opcode")
                            }
                            let actual = try integer(evaluate(bit, [bits(a, width), bits(b, width)])[0])
                            #expect(actual == expected, "width=\(width), signed=\(signed), op=\(operation), a=\(a), b=\(b)")
                        }
                    }
                }
            }
        }
    }

    @Test func exhaustiveUnaryAndSelection() throws {
        for width in 1...5 {
            let mask = (1 << width) - 1
            for operation: WordLogicOpcode in [.invert, .negate, .logicalNot, .reduceAnd, .reduceOr, .reduceXor] {
                let boolean = operation != .invert && operation != .negate
                let bit = try lower(graph(operation, inputs: [type(width)], output: type(boolean ? 1 : width)))
                for a in 0...mask {
                    let expected: Int
                    switch operation {
                    case .invert: expected = ~a & mask
                    case .negate: expected = -a & mask
                    case .logicalNot: expected = a == 0 ? 1 : 0
                    case .reduceAnd: expected = a == mask ? 1 : 0
                    case .reduceOr: expected = a != 0 ? 1 : 0
                    case .reduceXor: expected = a.nonzeroBitCount & 1
                    default: throw LogicKernelError.invalidModel("Unexpected unary opcode")
                    }
                    #expect(try integer(evaluate(bit, [bits(a, width)])[0]) == expected)
                }
            }
            let select = try lower(graph(.select, inputs: [type(1), type(width), type(width)], output: type(width)))
            for a in 0...mask {
                for b in 0...mask {
                    for control in 0...1 {
                        #expect(try integer(evaluate(select, [bits(control, 1), bits(a, width), bits(b, width)])[0]) == (control == 1 ? a : b))
                    }
                }
            }
        }
    }

    @Test func extensionsSlicesConcatenationAndOrigins() throws {
        let artifact = try ArtifactReference(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: String(repeating: "a", count: 64)), byteCount: 100,
            descriptor: ArtifactDescriptor(role: .input, kind: .netlist, format: .json))
        let origin = try LogicKernelSourceRange(artifactID: artifact.id, byteRange: 7..<19)
        let extended = try lower(graph(.signExtend, inputs: [type(3, signed: true)], output: type(7, signed: true), origin: origin))
        #expect(try integer(evaluate(extended, [bits(5, 3)])[0]) == 125)
        #expect(extended.withNodes { nodes in nodes.indices.dropFirst(2).allSatisfy { nodes[$0].origin == origin } })
        let zero = try lower(graph(.zeroExtend, inputs: [type(3)], output: type(7)))
        #expect(try integer(evaluate(zero, [bits(5, 3)])[0]) == 5)
        let cast = try lower(graph(.bitcast, inputs: [type(3, signed: true)], output: type(3)))
        #expect(try integer(evaluate(cast, [bits(5, 3)])[0]) == 5)
        let slice = try lower(graph(.slice(offset: 2), inputs: [type(7)], output: type(3)))
        #expect(try integer(evaluate(slice, [bits(108, 7)])[0]) == 3)
        let concat = try lower(graph(.concatenate, inputs: [type(2), type(3), type(1)], output: type(6)))
        #expect(try integer(evaluate(concat, [bits(2, 2), bits(5, 3), bits(1, 1)])[0]) == 43)
    }

    @Test func wideCarryAndUnboundedShiftAmount() throws {
        let wide = try lower(graph(.add, inputs: [type(257), type(257)], output: type(257)))
        let result = try evaluate(wide, [[Bool](repeating: true, count: 257), [true] + [Bool](repeating: false, count: 256)])[0]
        #expect(result.allSatisfy { !$0 })
        var negative = [Bool](repeating: false, count: 129); negative[128] = true
        var amount = [Bool](repeating: false, count: 257); amount[256] = true
        let shift = try lower(graph(.shiftRight(arithmetic: true), inputs: [type(129, signed: true), type(257)], output: type(129, signed: true)))
        #expect(try evaluate(shift, [negative, amount])[0].allSatisfy { $0 })
        let left = try lower(graph(.shiftLeft, inputs: [type(129), type(257)], output: type(129)))
        #expect(try evaluate(left, [negative, amount])[0].allSatisfy { !$0 })
    }

    @Test func renamedIdentitiesDoNotChangeConnectivityOrBehavior() throws {
        let first = try lower(graph(.subtract, inputs: [type(5), type(5)], output: type(5)))
        let second = try lower(graph(.subtract, inputs: [type(5), type(5)], output: type(5), reverseIDs: true))
        for a in 0..<32 { for b in 0..<32 {
            #expect(try evaluate(first, [bits(a, 5), bits(b, 5)]) == evaluate(second, [bits(a, 5), bits(b, 5)]))
        } }
    }

    @Test func lowersConstantsAndPropagatesControlAndStorageFailures() throws {
        var sourceContext = try context()
        var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 1, operands: 0, ports: 1, states: 0), context: &sourceContext)
        let value = try LogicFourStateVector(width: LogicBitWidth(9), valueWords: [303], unknownWords: [0])
        let word = try builder.addNode(id: id(1), type: type(9), operation: .constant(value), context: &sourceContext)
        try builder.addPort(WordLogicPort(id: id(2), direction: .output, value: word), context: &sourceContext)
        let constant = try builder.finish(context: &sourceContext)
        #expect(try integer(evaluate(lower(constant), [])[0]) == 303)
        let valid = try graph(.add, inputs: [type(9), type(9)], output: type(9))
        for failure in [LogicKernelError.cancelled, .deadlineExceeded] {
            var context = try context(control: Control(failure))
            #expect(throws: failure) { try NativeLogicBitLowering().lower(valid, context: &context) }
        }
        var tiny = try context(storage: 1)
        do { _ = try NativeLogicBitLowering().lower(valid, context: &tiny); Issue.record("Storage limit was ignored") }
        catch {
            guard case .resourceLimit(resource: .managedStorageBytes, limit: 1, requested: _) = error else { throw error }
        }
    }

    @Test func stateBitsPreserveClockGateEnableResetAndInitialRange() throws {
        for profile in 0..<3 {
            for explicitInitial in [false, true] {
                var context = try context()
                var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 5, operands: 0, ports: 6, states: 1), context: &context)
                for index in 0..<4 {
                    let word = try builder.addNode(id: id(index + 1), type: type(index == 0 ? 3 : 1), operation: .input, context: &context)
                    try builder.addPort(WordLogicPort(id: id(100 + index), direction: .input, value: word), context: &context)
                }
                let q = try builder.addNode(id: id(5), type: type(3), operation: .state(WordStateIndex(0)), context: &context)
                let resetValue = try LogicFourStateVector(width: LogicBitWidth(3), valueWords: [5], unknownWords: [0])
                let reset = WordReset(signal: WordNodeIndex(3), activeHigh: false, value: resetValue,
                                      kind: profile == 0 ? .synchronous : .asynchronous)
                let control: WordStateControl = profile == 2
                    ? .latch(gate: WordNodeIndex(1), activeHigh: false, reset: reset)
                    : .flipFlop(clock: WordNodeIndex(1), edge: .falling, enable: WordNodeIndex(2), reset: reset)
                let initial = explicitInitial ? try LogicFourStateVector(width: LogicBitWidth(3), valueWords: [6], unknownWords: [0]) : nil
                _ = try builder.addState(WordLogicState(id: id(6), next: WordNodeIndex(0), control: control, initialValue: initial), context: &context)
                try builder.addPort(WordLogicPort(id: id(200), direction: .output, value: q), context: &context)
                try builder.addPort(WordLogicPort(id: id(201), direction: .output, value: WordNodeIndex(0)), context: &context)
                let word = try builder.finish(context: &context)
                let bit = try lower(word)
                bit.withTables { _, _, ports, portBits, states, _ in
                    #expect(states.count == 3)
                    let clock = portBits[ports[1].bits.lowerBound]
                    let enable = portBits[ports[2].bits.lowerBound]
                    let resetSignal = portBits[ports[3].bits.lowerBound]
                    for index in states.indices {
                        let state = states[index]
                        #expect(state.next == portBits[ports[5].bits.lowerBound + index])
                        #expect(state.initialValue == (explicitInitial ? ((6 >> index) & 1 != 0) : nil))
                        let actualReset: BitReset?
                        switch state.control {
                        case .flipFlop(let actualClock, let edge, let actualEnable, let reset):
                            #expect(profile != 2 && actualClock == clock && edge == .falling && actualEnable == enable)
                            actualReset = reset
                        case .latch(let gate, let activeHigh, let reset):
                            #expect(profile == 2 && gate == clock && !activeHigh); actualReset = reset
                        }
                        #expect(actualReset?.signal == resetSignal && actualReset?.activeHigh == false)
                        #expect(actualReset?.value == ((5 >> index) & 1 != 0))
                        #expect(actualReset?.kind == (profile == 0 ? .synchronous : .asynchronous))
                    }
                }
                let observation = try evaluate(bit, [bits(6, 3), [false], [true], [true]], state: [true, false, true])
                #expect(integer(observation[0]) == 5 && integer(observation[1]) == 6)
            }
        }
    }

    @Test func multipleStateWidthsRetainIndependentBitCorrespondence() throws {
        var context = try context()
        var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 5, operands: 0, ports: 5, states: 2), context: &context)
        for (index, width) in [1, 2, 5].enumerated() {
            let input = try builder.addNode(id: id(index + 1), type: type(width), operation: .input, context: &context)
            try builder.addPort(WordLogicPort(id: id(100 + index), direction: .input, value: input), context: &context)
        }
        for (index, width) in [2, 5].enumerated() {
            let q = try builder.addNode(id: id(4 + index), type: type(width), operation: .state(WordStateIndex(index)), context: &context)
            _ = try builder.addState(WordLogicState(id: id(10 + index), next: WordNodeIndex(index + 1),
                control: .flipFlop(clock: WordNodeIndex(0), edge: .rising, enable: nil, reset: nil)), context: &context)
            try builder.addPort(WordLogicPort(id: id(200 + index), direction: .output, value: q), context: &context)
        }
        let word = try builder.finish(context: &context)
        let bit = try lower(word)
        #expect(bit.stateCount == 7)
        let outputs = try evaluate(bit, [[false], bits(1, 2), bits(4, 5)], state: [false, true, true, false, true, false, true])
        #expect(integer(outputs[0]) == 2 && integer(outputs[1]) == 21)
        bit.withTables { _, _, ports, bindings, states, _ in
            for index in states.indices {
                let sourcePort = index < 2 ? 1 : 2; let offset = index < 2 ? index : index - 2
                #expect(states[index].next == bindings[ports[sourcePort].bits.lowerBound + offset])
            }
        }
    }

    @Test func representabilityOverflowIsAResourceFailureBeforeAllocation() throws {
        let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64.max) }))
        var source = LogicKernelContext(limits: limits, control: Control())
        var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 1, operands: 0, ports: 1, states: 0), context: &source)
        let input = try builder.addNode(id: id(1), type: type(Int.max), operation: .input, context: &source)
        try builder.addPort(WordLogicPort(id: id(2), direction: .input, value: input), context: &source)
        let word = try builder.finish(context: &source)
        var run = LogicKernelContext(limits: limits, control: Control())
        #expect(throws: LogicKernelError.resourceLimit(resource: .expansion, limit: UInt64.max, requested: nil)) {
            try NativeLogicBitLowering().lower(word, context: &run)
        }
        #expect(run.usage[.managedStorageBytes] == 0 && run.usage.peakManagedStorageBytes == 0)
    }

    @Test func midExpansionFailureReleasesTemporaryStorageAndBudgetIsCumulative() throws {
        let word = try graph(.add, inputs: [type(9), type(9)], output: type(9))
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000_000)) })
        limits[.workUnits] = 60
        var bounded = LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: Control())
        do throws(LogicKernelError) {
            _ = try NativeLogicBitLowering().lower(word, context: &bounded)
            throw .invalidModel("Work-limited lowering returned a design")
        } catch {
            guard case .resourceLimit(resource: .workUnits, limit: 60, requested: _) = error else { throw error }
        }
        #expect(bounded.usage[.managedStorageBytes] > 0)
        #expect(bounded.usage.peakManagedStorageBytes > bounded.usage[.managedStorageBytes])
        var run = try context()
        _ = try NativeLogicBitLowering().lower(word, context: &run)
        let expansion = run.usage[.expansion]; let retained = run.usage[.managedStorageBytes]
        _ = try NativeLogicBitLowering().lower(word, context: &run)
        #expect(run.usage[.expansion] == 2 * expansion)
        #expect(run.usage[.managedStorageBytes] == 2 * retained)
    }
}
