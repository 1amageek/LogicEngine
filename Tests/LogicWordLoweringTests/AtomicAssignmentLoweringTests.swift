import Testing
import LogicIR
import LogicKernelCore
import LogicLowering

@Suite(.timeLimit(.minutes(1)))
struct AtomicAssignmentLoweringTests {
    @Test func blockingAndNBASwapsReadTheSamePreWriteValue() throws {
        for nba in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (_, data) = try f.signal(4, input: true, context: &source)
            let (q, readQ) = try f.signal(4, context: &source)
            let initial = try f.assign(q, data, range: 0..<4, context: &source)
            let low = try f.compute(.slice(offset: 0), width: 2, [readQ], context: &source)
            let high = try f.compute(.slice(offset: 2), width: 2, [readQ], context: &source)
            let first = try f.assign(q, low, range: 2..<4, nba: nba, context: &source)
            let second = try f.assign(q, high, range: 0..<2, nba: nba, context: &source)
            let group = try f.atomic([first, second], context: &source)
            let body = try f.block([initial, group], context: &source)
            try f.process(body, context: &source); try f.output(q, context: &source)
            let bit = try WordLoweringReference.lower(f.finish(context: &source))
            for value in 0..<16 {
                let result = try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(value, width: 4)])
                #expect(WordLoweringReference.integer(result.outputs[0]) == (value << 2 | value >> 2) & 15)
            }
        }
    }

    @Test func nestedGroupsSampleGuardsBeforeAnEarlierChildWritesTheirAddress() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, address) = try f.signal(input: true, context: &source)
        let (i, readI) = try f.signal(context: &source)
        let (q, _) = try f.signal(2, context: &source)
        let one = try f.constant(1, context: &source)
        let zeros = try f.constant(0, width: 2, context: &source)
        let initI = try f.assign(i, address, context: &source)
        let initQ = try f.assign(q, zeros, range: 0..<2, context: &source)
        let changeAddress = try f.assign(i, one, context: &source)
        let writeHigh = try f.assign(q, one, range: 1..<2, context: &source)
        let writeLow = try f.assign(q, one, context: &source)
        let conditional = try f.branch(readI, writeHigh, writeLow, context: &source)
        let nested = try f.atomic([conditional], context: &source)
        let group = try f.atomic([changeAddress, nested], context: &source)
        let body = try f.block([initI, initQ, group], context: &source)
        try f.process(body, context: &source); try f.output(i, context: &source); try f.output(q, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        for value in [false, true] {
            let result = try WordLoweringReference.run(bit, inputs: [[value]])
            #expect(result.outputs[0] == [true])
            #expect(WordLoweringReference.integer(result.outputs[1]) == (value ? 2 : 1))
        }
    }

    @Test func completeConditionalGroupsRetainCompletenessAndLaterWritePriority() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, condition) = try f.signal(input: true, context: &source)
        let (_, input) = try f.signal(2, input: true, context: &source)
        let (q, _) = try f.signal(2, context: &source)
        let zero = try f.constant(0, width: 2, context: &source)
        let one = try f.constant(1, context: &source)
        let yes = try f.assign(q, input, range: 0..<2, context: &source)
        let no = try f.assign(q, zero, range: 0..<2, context: &source)
        let branch = try f.branch(condition, yes, no, context: &source)
        let final = try f.assign(q, one, context: &source)
        let group = try f.atomic([branch, final], context: &source)
        try f.process(group, context: &source); try f.output(q, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        for condition in [false, true] { for value in 0..<4 {
            let result = try WordLoweringReference.run(bit, inputs: [[condition], WordLoweringReference.bits(value, width: 2)])
            #expect(WordLoweringReference.integer(result.outputs[0]) == (condition ? value | 1 : 1))
        } }
    }

    @Test func sequentialGroupsPreserveStateAndConditionalNBAOverride() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, clock) = try f.signal(input: true, context: &source)
        let (_, enabled) = try f.signal(input: true, context: &source)
        let (q, readQ) = try f.signal(2, context: &source)
        let low = try f.compute(.slice(offset: 0), width: 1, [readQ], context: &source)
        let high = try f.compute(.slice(offset: 1), width: 1, [readQ], context: &source)
        let first = try f.assign(q, low, range: 1..<2, context: &source)
        let second = try f.assign(q, high, nba: true, context: &source)
        let scheduled = try f.branch(enabled, second, context: &source)
        let group = try f.atomic([first, scheduled], context: &source)
        try f.process(group, control: .flipFlop(clock: clock, edge: .rising, asynchronousReset: nil), context: &source)
        try f.output(q, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        #expect(bit.stateCount == 2)
        for value in 0..<4 { for enabled in [false, true] {
            let result = try WordLoweringReference.run(bit, inputs: [[false], [enabled]], state: WordLoweringReference.bits(value, width: 2))
            #expect(WordLoweringReference.integer(result.next) == ((value & 1) << 1 | (enabled ? value >> 1 : value & 1)))
        } }
    }

    @Test func constantDeadGuardsAvoidUnknownDataButLiveUnknownsAreRejected() throws {
        for live in [false, true] {
            var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
            let (q, _) = try f.signal(context: &source)
            let test = try f.constant(live ? 1 : 0, context: &source)
            let unknown = try f.constant(0, unknown: 1, context: &source)
            let one = try f.constant(1, context: &source)
            let yes = try f.assign(q, unknown, context: &source)
            let no = try f.assign(q, one, context: &source)
            let branch = try f.branch(test, yes, no, context: &source)
            let group = try f.atomic([branch], context: &source)
            try f.process(group, context: &source); try f.output(q, context: &source)
            let rtl = try f.finish(context: &source)
            if live {
                #expect(throws: LogicKernelError.self) { try WordLoweringReference.lower(rtl) }
            } else {
                let bit = try WordLoweringReference.lower(rtl)
                #expect(try WordLoweringReference.run(bit, inputs: []).outputs[0] == [true])
            }
        }
    }

    @Test func separateGroupsResampleAfterEarlierGroupsAndAnEmptyGroupEndsNormally() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, input) = try f.signal(2, input: true, context: &source)
        let (q, readQ) = try f.signal(2, context: &source)
        let low = try f.compute(.slice(offset: 0), width: 1, [readQ], context: &source)
        let high = try f.compute(.slice(offset: 1), width: 1, [readQ], context: &source)
        let initial = try f.assign(q, input, range: 0..<2, context: &source)
        let first = try f.assign(q, low, range: 1..<2, context: &source)
        let second = try f.assign(q, high, context: &source)
        let firstGroup = try f.atomic([first, second], context: &source)
        let empty = try f.atomic([], context: &source)
        let secondGroup = try f.atomic([first, second], context: &source)
        let body = try f.block([initial, firstGroup, empty, secondGroup], context: &source)
        try f.process(body, context: &source); try f.output(q, context: &source)
        let bit = try WordLoweringReference.lower(f.finish(context: &source))
        for value in 0..<4 {
            #expect(try WordLoweringReference.run(bit, inputs: [WordLoweringReference.bits(value, width: 2)]).outputs[0]
                == WordLoweringReference.bits(value, width: 2))
        }
    }

    @Test func failedGroupRunsReleaseWorkspaceAndNeverPublishPartialResults() throws {
        var source = try RTLFixture.context(); var f = try RTLFixture.make(context: &source)
        let (_, input) = try f.signal(4, input: true, context: &source)
        let (q, _) = try f.signal(4, context: &source)
        let write = try f.assign(q, input, range: 0..<4, context: &source)
        let group = try f.atomic([write], context: &source)
        try f.process(group, context: &source); try f.output(q, context: &source)
        let rtl = try f.finish(context: &source)
        for mode in 0..<3 {
            var context = try RTLFixture.context(storage: mode == 0 ? 1 : 1_000_000_000,
                work: mode == 1 ? 1 : 1_000_000_000, control: RTLFixture.Control(mode == 2 ? .cancelled : nil))
            #expect(throws: LogicKernelError.self) { try NativeLogicWordLowering().lower(rtl, context: &context) }
            // The invocation retains charges for scalar constant payloads, separately from workspace storage.
            #expect(context.usage[.managedStorageBytes] == (mode == 1 ? 32 : 0))
        }
    }
}
