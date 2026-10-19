import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicLowering

@Suite(.timeLimit(.minutes(1)))
struct ProceduralLoweringTests {
    @Test func crossProcessFFBlockingRaceIsRejectedWithoutRejectingNBA() throws {
        for blocking in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(input: true, context: &source)
            let (_, clock) = try f.signal(input: true, context: &source)
            let (q, readQ) = try f.signal(context: &source)
            let (r, _) = try f.signal(context: &source)
            let writeQ = try f.assign(q, data, nba: !blocking, context: &source)
            let writeR = try f.assign(r, readQ, nba: true, context: &source)
            try f.process(writeQ, control: .flipFlop(clock: clock, edge: .rising, asynchronousReset: nil), context: &source)
            try f.process(writeR, control: .flipFlop(clock: clock, edge: .rising, asynchronousReset: nil), context: &source)
            try f.output(r, context: &source)
            let rtl = try f.finish(context: &source)
            if blocking {
                #expect(throws: LogicKernelError.self) { try WordLoweringReference.lower(rtl) }
            } else {
                let bit = try WordLoweringReference.lower(rtl)
                for old in [false, true] { for data in [false, true] {
                    let result = try WordLoweringReference.run(bit, inputs: [[data], [false]], state: [old, !old])
                    #expect(result.next == [data, old])
                } }
            }
        }
    }

    @Test func raceAdmissionTracksSelectedBitsAndCombinationalIntermediates() throws {
        for indirect in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(2, input: true, context: &source)
            let (_, clock) = try f.signal(input: true, context: &source)
            let (q, readQ) = try f.signal(2, context: &source)
            let (wire, readWire) = try f.signal(2, context: &source)
            let (r, _) = try f.signal(context: &source)
            let low = try f.compute(.slice(offset: 0), width: 1, [data], context: &source)
            let high = try f.compute(.slice(offset: 1), width: 1, [data], context: &source)
            let lowWrite = try f.assign(q, low, range: 0..<1, context: &source)
            let highWrite = try f.assign(q, high, range: 1..<2, nba: true, context: &source)
            let body = try f.block([lowWrite, highWrite], context: &source)
            let passthrough = try f.assign(wire, readQ, range: 0..<2, context: &source)
            let selected = try f.compute(.slice(offset: indirect ? 0 : 1), width: 1, [readWire], context: &source)
            let read = try f.assign(r, selected, nba: true, context: &source)
            try f.process(body, control: .flipFlop(clock: clock, edge: .rising, asynchronousReset: nil), context: &source)
            try f.process(passthrough, control: .continuous, context: &source)
            try f.process(read, control: .flipFlop(clock: clock, edge: .rising, asynchronousReset: nil), context: &source)
            try f.output(r, context: &source)
            let rtl = try f.finish(context: &source)
            if indirect {
                #expect(throws: LogicKernelError.self) { try WordLoweringReference.lower(rtl) }
            } else {
                let bit = try WordLoweringReference.lower(rtl)
                for old in 0..<4 {
                    let result = try WordLoweringReference.run(bit, inputs: [[false, false], [false]],
                        state: WordLoweringReference.bits(old, width: 2) + [false])
                    #expect(result.next == [false, false, old & 2 != 0])
                }
            }
        }
    }

    @Test func asynchronousResetRefusesIncompleteNonconstantAndUnmatchedBranches() throws {
        for mode in 0..<4 {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(3, input: true, context: &source)
            let (_, reset) = try f.signal(input: true, context: &source)
            let (_, clock) = try f.signal(input: true, context: &source)
            let (_, other) = try f.signal(input: true, context: &source)
            let (q, _) = try f.signal(3, initial: mode == 3 ? RTLFixture.vector(0, width: 3, unknown: 1) : nil, context: &source)
            let value = try f.constant(0, width: mode == 2 ? 1 : 3, context: &source)
            let asserted = try f.assign(q, mode == 1 ? data : value, range: mode == 2 ? 0..<1 : 0..<3, nba: true, context: &source)
            let normal = try f.assign(q, data, range: 0..<3, nba: true, context: &source)
            let body = try f.branch(mode == 0 ? other : reset, asserted, normal, context: &source)
            try f.process(body, control: .flipFlop(clock: clock, edge: .rising,
                asynchronousReset: RTLResolvedReset(signal: reset, activeHigh: true)), context: &source)
            try f.output(q, context: &source)
            let rtl = try f.finish(context: &source)
            #expect(throws: LogicKernelError.self) { try WordLoweringReference.lower(rtl) }
        }
    }

    @Test func constantResetArithmeticAndSynchronousPriorityArePreserved() throws {
        for shape in 0..<3 {
            let asynchronous = shape != 0
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(3, input: true, context: &source)
            let (_, reset) = try f.signal(input: true, context: &source)
            let (_, enable) = try f.signal(input: true, context: &source)
            let (_, clock) = try f.signal(input: true, context: &source)
            let (q, _) = try f.signal(3, context: &source)
            let three = try f.constant(3, width: 3, context: &source)
            let two = try f.constant(2, width: 3, context: &source)
            let five: RTLExpressionIndex
            if shape == 2 {
                let upper = try f.constant(2, width: 2, context: &source)
                let lower = try f.constant(1, context: &source)
                five = try f.compute(.concatenate, width: 3, [upper, lower], context: &source)
            } else { five = try f.compute(.add, width: 3, [three, two], context: &source) }
            let resetWrite = try f.assign(q, five, range: 0..<3, nba: true, context: &source)
            let dataWrite = try f.assign(q, data, range: 0..<3, nba: true, context: &source)
            let enabled = try f.branch(enable, dataWrite, context: &source)
            let body = try f.branch(reset, resetWrite, enabled, context: &source)
            try f.process(body, control: .flipFlop(clock: clock, edge: .rising,
                asynchronousReset: asynchronous ? RTLResolvedReset(signal: reset, activeHigh: true) : nil), context: &source)
            try f.output(q, context: &source)
            let bit = try WordLoweringReference.lower(f.finish(context: &source))
            for old in 0..<8 { for data in 0..<8 { for reset in [false, true] { for enabled in [false, true] {
                let next = try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(data, width: 3), [reset], [enabled], [false]],
                    state: WordLoweringReference.bits(old, width: 3)).next
                #expect(WordLoweringReference.integer(next) == (reset ? 5 : enabled ? data : old))
            } } } }
        }
    }

    @Test func constantOperationsRetainResolvedSignedAndModularMeaning() throws {
        let operations: [WordLogicOpcode] = [.add, .subtract, .multiply, .and, .or, .xor, .equal, .lessThan,
            .logicalAnd, .logicalOr, .shiftLeft, .shiftRight(arithmetic: false), .shiftRight(arithmetic: true)]
        for signed in [false, true] { for operation in operations { for a in [0, 7, 8, 15] { for b in [0, 1, 4, 15] {
            let comparison = [.equal, .lessThan, .logicalAnd, .logicalOr].contains(operation)
            let shift = operation == .shiftLeft || operation == .shiftRight(arithmetic: false) || operation == .shiftRight(arithmetic: true)
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let left = try f.constant(UInt64(a), width: 4, signed: signed, context: &source)
            let right = try f.constant(UInt64(b), width: 4, signed: signed && !shift, context: &source)
            let result = try f.compute(operation, width: comparison ? 1 : 4, signed: signed && !comparison, [left, right], context: &source)
            let (y, _) = try f.signal(comparison ? 1 : 4, signed: signed && !comparison, context: &source)
            let body = try f.assign(y, result, range: comparison ? 0..<1 : 0..<4, context: &source)
            try f.process(body, context: &source); try f.output(y, context: &source)
            let bit = try WordLoweringReference.lower(f.finish(context: &source))
            let sa = signed && a >= 8 ? a - 16 : a; let sb = signed && b >= 8 ? b - 16 : b
            let expected: Int
            switch operation {
            case .add: expected = (a + b) & 15
            case .subtract: expected = (a - b) & 15
            case .multiply: expected = (a * b) & 15
            case .and: expected = a & b
            case .or: expected = a | b
            case .xor: expected = a ^ b
            case .equal: expected = a == b ? 1 : 0
            case .lessThan: expected = sa < sb ? 1 : 0
            case .logicalAnd: expected = a != 0 && b != 0 ? 1 : 0
            case .logicalOr: expected = a != 0 || b != 0 ? 1 : 0
            case .shiftLeft: expected = b >= 4 ? 0 : a << b & 15
            case .shiftRight(arithmetic: false): expected = b >= 4 ? 0 : a >> b
            case .shiftRight(arithmetic: true): expected = sa >> min(b, 4) & 15
            default: throw LogicKernelError.invalidModel("Unexpected reference opcode")
            }
            #expect(try WordLoweringReference.integer(WordLoweringReference.run(bit, inputs: []).outputs[0]) == expected)
        } } } }
        for operation: WordLogicOpcode in [.invert, .negate, .logicalNot, .reduceAnd, .reduceOr, .reduceXor,
            .bitcast, .zeroExtend, .signExtend, .slice(offset: 1)] {
            for value in [0, 1, 7, 8, 15] {
                var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
                let boolean = [.logicalNot, .reduceAnd, .reduceOr, .reduceXor].contains(operation)
                let extend = operation == .zeroExtend || operation == .signExtend
                let width = boolean ? 1 : extend ? 9 : operation == .slice(offset: 1) ? 2 : 4
                let sourceValue = try f.constant(UInt64(value), width: 4, signed: operation == .signExtend, context: &source)
                let result = try f.compute(operation, width: width, signed: operation == .signExtend, [sourceValue], context: &source)
                let (y, _) = try f.signal(width, signed: operation == .signExtend, context: &source)
                let body = try f.assign(y, result, range: 0..<width, context: &source)
                try f.process(body, context: &source); try f.output(y, context: &source)
                let bit = try WordLoweringReference.lower(f.finish(context: &source))
                let expected: Int
                switch operation {
                case .invert: expected = ~value & 15
                case .negate: expected = -value & 15
                case .logicalNot: expected = value == 0 ? 1 : 0
                case .reduceAnd: expected = value == 15 ? 1 : 0
                case .reduceOr: expected = value != 0 ? 1 : 0
                case .reduceXor: expected = value.nonzeroBitCount & 1
                case .signExtend: expected = value >= 8 ? value + 496 : value
                case .slice: expected = value >> 1 & 3
                default: expected = value
                }
                #expect(try WordLoweringReference.integer(WordLoweringReference.run(bit, inputs: []).outputs[0]) == expected)
            }
        }
    }

    @Test func unobservedUnknownStorageIsNotInventedAsZeroAndWidePortsRemainExact() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, input) = try f.signal(257, input: true, signed: true, context: &source)
        _ = try f.signal(5, initial: RTLFixture.vector(0, width: 5, unknown: 31), context: &source)
        let (y, _) = try f.signal(257, signed: true, context: &source)
        let body = try f.assign(y, input, range: 0..<257, context: &source)
        try f.process(body, control: .levelSensitive, context: &source); try f.output(y, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        var inputBits = [Bool](repeating: false, count: 257); inputBits[0] = true; inputBits[128] = true; inputBits[256] = true
        #expect(try WordLoweringReference.run(bit, inputs: [inputBits]).outputs[0] == inputBits)
        #expect(bit.stateCount == 0)
    }
    @Test func orderedPartialWritesHaveNoDiscardedOldValueCycle() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, a) = try f.signal(3, input: true, context: &source)
        let (y, readY) = try f.signal(3, context: &source)
        var writes: [RTLStatementIndex] = []
        for bit in 0..<3 {
            let selected = try f.compute(.slice(offset: bit), width: 1, [a], context: &source)
            writes.append(try f.assign(y, selected, range: bit..<(bit + 1), context: &source))
        }
        let one = try f.constant(1, width: 3, context: &source)
        let increment = try f.compute(.add, width: 3, [readY, one], context: &source)
        writes.append(try f.assign(y, increment, range: 0..<3, context: &source))
        let body = try f.block(writes, context: &source)
        try f.process(body, context: &source); try f.output(y, context: &source)
        let rtl = try f.finish(context: &source); let bit = try WordLoweringReference.lower(rtl)
        for value in 0..<8 {
            #expect(try WordLoweringReference.integer(WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(value, width: 3)]).outputs[0]) == (value + 1) % 8)
        }
    }

    @Test func nestedBranchesJoinOnlyTheirWritesAndPreserveLaterReads() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, a) = try f.signal(3, input: true, context: &source)
        let (_, b) = try f.signal(3, input: true, context: &source)
        let (_, c) = try f.signal(input: true, context: &source)
        let (_, d) = try f.signal(input: true, context: &source)
        let (y, readY) = try f.signal(3, context: &source)
        let zero = try f.constant(0, width: 3, context: &source)
        let assignA = try f.assign(y, a, range: 0..<3, context: &source)
        let assignB = try f.assign(y, b, range: 0..<3, context: &source)
        let assignZero = try f.assign(y, zero, range: 0..<3, context: &source)
        let inner = try f.branch(d, assignA, assignB, context: &source)
        let outer = try f.branch(c, inner, assignZero, context: &source)
        let one = try f.constant(1, width: 3, context: &source)
        let addition = try f.compute(.add, width: 3, [readY, one], context: &source)
        let final = try f.assign(y, addition, range: 0..<3, context: &source)
        let body = try f.block([outer, final], context: &source)
        try f.process(body, context: &source); try f.output(y, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        for av in 0..<8 { for bv in 0..<8 { for cv in 0...1 { for dv in 0...1 {
            let actual = try WordLoweringReference.integer(WordLoweringReference.run(bit, inputs: [
                WordLoweringReference.bits(av, width: 3), WordLoweringReference.bits(bv, width: 3), [cv == 1], [dv == 1]]).outputs[0])
            #expect(actual == ((cv == 1 ? (dv == 1 ? av : bv) : 0) + 1) % 8)
        } } } }
    }

    @Test func conditionalNBADoesNotCaptureTheOldBlockingFallback() throws {
        for sequential in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(2, input: true, context: &source)
            let (_, condition) = try f.signal(input: true, context: &source)
            let (_, clock) = try f.signal(input: true, context: &source)
            let (q, _) = try f.signal(2, context: &source)
            let schedule = try f.assign(q, data, range: 0..<2, nba: true, context: &source)
            let guarded = try f.branch(condition, schedule, context: &source)
            let two = try f.constant(2, width: 2, context: &source)
            let blocking = try f.assign(q, two, range: 0..<2, context: &source)
            let body = try f.block([guarded, blocking], context: &source)
            try f.process(body, control: sequential ? .flipFlop(clock: clock, edge: .falling, asynchronousReset: nil) : .combinational, context: &source)
            try f.output(q, context: &source)
            let bit = try WordLoweringReference.lower(f.finish(context: &source))
            for old in 0..<4 { for value in 0..<4 { for active in [false, true] {
                let result = try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(value, width: 2), [active], [false]],
                    state: sequential ? WordLoweringReference.bits(old, width: 2) : [])
                #expect(WordLoweringReference.integer(sequential ? result.next : result.outputs[0]) == (active ? value : 2))
            } } }
        }
    }

    @Test func mixedBlockingAndNBAPathsProduceACompleteCombinationalValue() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, condition) = try f.signal(input: true, context: &source)
        let (_, a) = try f.signal(3, input: true, context: &source)
        let (_, b) = try f.signal(3, input: true, context: &source)
        let (y, _) = try f.signal(3, context: &source)
        let yes = try f.assign(y, a, range: 0..<3, context: &source)
        let no = try f.assign(y, b, range: 0..<3, nba: true, context: &source)
        let body = try f.branch(condition, yes, no, context: &source)
        try f.process(body, context: &source); try f.output(y, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        for a in 0..<8 { for b in 0..<8 { for condition in [false, true] {
            let actual = try WordLoweringReference.integer(WordLoweringReference.run(bit,
                inputs: [[condition], WordLoweringReference.bits(a, width: 3), WordLoweringReference.bits(b, width: 3)]).outputs[0])
            #expect(actual == (condition ? a : b))
        } } }
    }

    @Test func NBACapturesRHSBeforeCommitAndLastScheduledWriteWins() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, data) = try f.signal(2, input: true, context: &source)
        let (_, condition) = try f.signal(input: true, context: &source)
        let (_, clock) = try f.signal(input: true, context: &source)
        let (q, readQ) = try f.signal(2, context: &source)
        let (r, _) = try f.signal(2, context: &source)
        let one = try f.constant(1, width: 2, context: &source)
        let increment = try f.compute(.add, width: 2, [readQ, one], context: &source)
        let first = try f.assign(q, data, range: 0..<2, nba: true, context: &source)
        let blocking = try f.assign(q, increment, range: 0..<2, context: &source)
        let capture = try f.assign(r, readQ, range: 0..<2, nba: true, context: &source)
        let last = try f.assign(q, readQ, range: 0..<2, nba: true, context: &source)
        let guarded = try f.branch(condition, last, context: &source)
        let body = try f.block([first, blocking, capture, guarded], context: &source)
        try f.process(body, control: .flipFlop(clock: clock, edge: .rising, asynchronousReset: nil), context: &source)
        try f.output(q, context: &source); try f.output(r, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        for q in 0..<4 { for r in 0..<4 { for data in 0..<4 { for condition in [false, true] {
            let result = try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(data, width: 2), [condition], [true]],
                state: WordLoweringReference.bits(q, width: 2) + WordLoweringReference.bits(r, width: 2))
            let increment = (q + 1) % 4
            #expect(WordLoweringReference.integer(Array(result.next[0..<2])) == (condition ? increment : data))
            #expect(WordLoweringReference.integer(Array(result.next[2..<4])) == increment)
        } } } }
    }

    @Test func ordinaryCaseUsesFirstMatchAndProvesLiteralDomainCoverage() throws {
        for duplicate in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, selector) = try f.signal(2, input: true, context: &source)
            let (y, _) = try f.signal(3, context: &source)
            var armBodies: [RTLStatementIndex] = []; var patterns: [[RTLExpressionIndex]] = []
            for value in (duplicate ? [0, 0, 1, 2, 3] : [0, 1, 2, 3]) {
                patterns.append([try f.constant(UInt64(value), width: 2, context: &source)])
                let result = try f.constant(UInt64(armBodies.count + 1), width: 3, context: &source)
                armBodies.append(try f.assign(y, result, range: 0..<3, context: &source))
            }
            for index in armBodies.indices {
                _ = try f.builder.addCaseItem(matches: patterns[index], body: armBodies[index], context: &source)
            }
            let statementID = try f.id()
            let body = try f.builder.addStatement(RTLResolvedStatement(id: statementID,
                operation: .caseStatement(selector: selector, items: 0..<armBodies.count, defaultBody: nil)), context: &source)
            try f.process(body, context: &source); try f.output(y, context: &source)
            let bit = try WordLoweringReference.lower(f.finish(context: &source))
            for value in 0..<4 {
                let expected = value == 0 ? 1 : value + (duplicate ? 2 : 1)
                #expect(try WordLoweringReference.integer(WordLoweringReference.run(bit,
                    inputs: [WordLoweringReference.bits(value, width: 2)]).outputs[0]) == expected)
            }
        }
    }

    @Test func latchGateHoldPolarityInitialAndTransparentFeedbackAreExplicit() throws {
        for high in [false, true] { for feedback in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(3, input: true, context: &source)
            let (_, gate) = try f.signal(input: true, context: &source)
            let (q, readQ) = try f.signal(3, initial: RTLFixture.vector(5, width: 3), context: &source)
            let condition = high ? gate : try f.compute(.logicalNot, width: 1, [gate], context: &source)
            let write = try f.assign(q, feedback ? readQ : data, range: 0..<3, context: &source)
            let body = try f.branch(condition, write, context: &source)
            try f.process(body, control: .latch, context: &source); try f.output(q, context: &source)
            let rtl = try f.finish(context: &source)
            if feedback {
                #expect(throws: LogicKernelError.self) { try WordLoweringReference.lower(rtl) }
                continue
            }
            let bit = try WordLoweringReference.lower(rtl)
            bit.withTables { _, _, _, _, states, _ in
                #expect(states.count == 3)
                for index in states.indices {
                    #expect(states[index].initialValue == (5 & (1 << index) != 0))
                    guard case .latch(_, let actualHigh, _) = states[index].control else { Issue.record("Lost latch control"); continue }
                    #expect(actualHigh == high)
                }
            }
            for old in 0..<8 { for data in 0..<8 { for gate in [false, true] {
                let result = try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(data, width: 3), [gate]],
                    state: WordLoweringReference.bits(old, width: 3))
                #expect(WordLoweringReference.integer(result.next) == (gate == high ? data : old))
            } } }
        } }
    }

    @Test func inferredLatchesRetainSignalOrderAcrossProcessesAndCompleteBits() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, data) = try f.signal(3, input: true, context: &source)
        let (_, gate) = try f.signal(input: true, context: &source)
        let (first, _) = try f.signal(2, context: &source)
        let (second, _) = try f.signal(3, context: &source)
        let (wire, _) = try f.signal(3, context: &source)
        let lower = try f.compute(.slice(offset: 0), width: 2, [data], context: &source)
        let writeFirst = try f.assign(first, lower, range: 0..<2, context: &source)
        let writeSecond = try f.assign(second, data, range: 0..<3, context: &source)
        let writeWire = try f.assign(wire, data, range: 0..<3, context: &source)
        let guardedFirst = try f.branch(gate, writeFirst, context: &source)
        let guardedSecond = try f.branch(gate, writeSecond, context: &source)
        let body = try f.block([guardedFirst, writeWire], context: &source)
        // An explicit latch is allocated before a lower signal's inferred latch.
        try f.process(guardedSecond, control: .latch, context: &source)
        try f.process(body, control: .levelSensitive, context: &source)
        try f.output(first, context: &source); try f.output(second, context: &source); try f.output(wire, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        #expect(bit.stateCount == 5)
        for first in 0..<4 { for second in 0..<8 { for data in 0..<8 { for gate in [false, true] {
            let result = try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(data, width: 3), [gate]],
                state: WordLoweringReference.bits(first, width: 2) + WordLoweringReference.bits(second, width: 3))
            #expect(WordLoweringReference.integer(result.outputs[0]) == first)
            #expect(WordLoweringReference.integer(result.outputs[1]) == second)
            #expect(WordLoweringReference.integer(result.outputs[2]) == data)
            #expect(WordLoweringReference.integer(Array(result.next[0..<2])) == (gate ? data & 3 : first))
            #expect(WordLoweringReference.integer(Array(result.next[2..<5])) == (gate ? data : second))
        } } } }
    }

    @Test func asynchronousResetKeepsActualControlPriorityAndEnable() throws {
        for high in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(3, input: true, context: &source)
            let (_, enable) = try f.signal(input: true, context: &source)
            let (_, clock) = try f.signal(input: true, context: &source)
            let (_, reset) = try f.signal(input: true, context: &source)
            let (q, _) = try f.signal(3, context: &source)
            let resetValue = try f.constant(5, width: 3, context: &source)
            let resetWrite = try f.assign(q, resetValue, range: 0..<3, nba: true, context: &source)
            let dataWrite = try f.assign(q, data, range: 0..<3, nba: true, context: &source)
            let enabled = try f.branch(enable, dataWrite, context: &source)
            let condition = high ? reset : try f.compute(.logicalNot, width: 1, [reset], context: &source)
            let branch = try f.branch(condition, resetWrite, enabled, context: &source)
            let body = try f.block([branch], context: &source)
            try f.process(body, control: .flipFlop(clock: clock, edge: .falling,
                asynchronousReset: RTLResolvedReset(signal: reset, activeHigh: high)), context: &source)
            try f.output(q, context: &source)
            let bit = try WordLoweringReference.lower(f.finish(context: &source))
            bit.withTables { _, _, _, _, states, _ in
                for index in states.indices {
                    guard case .flipFlop(_, let edge, let enable, let reset) = states[index].control else { Issue.record("Lost FF"); continue }
                    #expect(edge == .falling && enable != nil && reset?.kind == .asynchronous && reset?.activeHigh == high)
                    #expect(reset?.value == (5 & (1 << index) != 0)); #expect(states[index].initialValue == nil)
                }
            }
            for old in 0..<8 { for data in 0..<8 { for enabled in [false, true] { for reset in [false, true] {
                let result = try WordLoweringReference.run(bit,
                    inputs: [WordLoweringReference.bits(data, width: 3), [enabled], [false], [reset]], state: WordLoweringReference.bits(old, width: 3))
                #expect(WordLoweringReference.integer(result.next) == (reset == high ? 5 : enabled ? data : old))
            } } } }
        }
    }

    @Test func resetComparisonRecognizesSeparateReadsOfTheSameSignal() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, data) = try f.signal(input: true, context: &source)
        let (resetSignal, reset) = try f.signal(input: true, context: &source)
        let (_, clock) = try f.signal(input: true, context: &source)
        let (q, _) = try f.signal(context: &source)
        let readID = try f.id()
        let otherRead = try f.builder.addExpression(id: readID, type: RTLFixture.type(1), operation: .read(resetSignal), context: &source)
        let zero = try f.constant(0, context: &source)
        let condition = try f.compute(.equal, width: 1, [otherRead, zero], context: &source)
        let resetWrite = try f.assign(q, zero, nba: true, context: &source)
        let dataWrite = try f.assign(q, data, nba: true, context: &source)
        let body = try f.branch(condition, resetWrite, dataWrite, context: &source)
        try f.process(body, control: .flipFlop(clock: clock, edge: .rising,
            asynchronousReset: RTLResolvedReset(signal: reset, activeHigh: false)), context: &source)
        try f.output(q, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        for data in [false, true] { for reset in [false, true] {
            #expect(try WordLoweringReference.run(bit, inputs: [[data], [reset], [true]], state: [true]).next == [reset && data])
        } }
    }

    @Test func binaryDynamicSelectionIsAdmittedOnlyWithinItsRange() throws {
        for width in [3, 4] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(width, input: true, context: &source)
            let (_, offset) = try f.signal(2, input: true, context: &source)
            let (y, _) = try f.signal(context: &source)
            let expressionID = try f.id()
            let selection = try f.builder.addExpression(id: expressionID, type: RTLFixture.type(1),
                operation: .dynamicSelect, inputs: [data, offset], context: &source)
            let body = try f.assign(y, selection, context: &source)
            try f.process(body, control: .continuous, context: &source); try f.output(y, context: &source)
            let rtl = try f.finish(context: &source)
            if width == 3 { #expect(throws: LogicKernelError.self) { try WordLoweringReference.lower(rtl) }; continue }
            let bit = try WordLoweringReference.lower(rtl)
            for data in 0..<16 { for offset in 0..<4 {
                #expect(try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(data, width: 4),
                    WordLoweringReference.bits(offset, width: 2)]).outputs[0] == [data & (1 << offset) != 0])
            } }
        }
    }

    @Test func incompleteCombinationalAndObservedUnknownValuesFailWithSource() throws {
        let artifact = try ArtifactReference(digest: ContentDigest(algorithm: .sha256, hexadecimalValue: String(repeating: "a", count: 64)),
            byteCount: 100, descriptor: ArtifactDescriptor(role: .input, kind: .netlist, format: .json))
        let origin = try LogicKernelSourceRange(artifactID: artifact.id, byteRange: 5..<10)
        for mode in 0..<4 {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, condition) = try f.signal(input: true, context: &source)
            let (y, _) = try f.signal(origin: origin, context: &source)
            if mode != 3 {
                let value = try f.constant(mode == 2 ? 1 : 0, unknown: mode == 0 ? 0 : 1, origin: origin, context: &source)
                let write = try f.assign(y, value, context: &source)
                let body = mode == 0 ? try f.branch(condition, write, context: &source) : write
                try f.process(body, context: &source)
            }
            try f.output(y, context: &source)
            let rtl = try f.finish(context: &source)
            do { _ = try WordLoweringReference.lower(rtl); Issue.record("Unsupported binary dependency was admitted") }
            catch let error as LogicKernelError {
                if mode != 0 {
                    guard case .sourceFailure(_, let actual, _) = error else { throw error }
                    #expect(actual == origin)
                }
            }
        }
    }

    @Test func loweringReleasesWorkspaceOnFailureAndSharesCumulativeBudget() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, a) = try f.signal(9, input: true, context: &source)
        let (y, _) = try f.signal(9, context: &source)
        let body = try f.assign(y, a, range: 0..<9, context: &source)
        try f.process(body, context: &source); try f.output(y, context: &source)
        let rtl = try f.finish(context: &source)
        for error: LogicKernelError in [.cancelled, .deadlineExceeded] {
            var context = try RTLFixture.context(control: .init(error))
            #expect(throws: error) { try NativeLogicWordLowering().lower(rtl, context: &context) }
            #expect(context.usage[.managedStorageBytes] == 0)
        }
        var limited = try RTLFixture.context(work: 40)
        #expect(throws: LogicKernelError.self) { try NativeLogicWordLowering().lower(rtl, context: &limited) }
        // Only the two retained scalar constant payloads are charged after failure.
        #expect(limited.usage[.managedStorageBytes] == 32)
        #expect(limited.usage.peakManagedStorageBytes > 32)
        var run = try RTLFixture.context()
        _ = try NativeLogicWordLowering().lower(rtl, context: &run)
        let retained = run.usage[.managedStorageBytes]; let expansion = run.usage[.expansion]
        _ = try NativeLogicWordLowering().lower(rtl, context: &run)
        #expect(run.usage[.managedStorageBytes] == retained * 2 && run.usage[.expansion] == expansion * 2)
    }
}
