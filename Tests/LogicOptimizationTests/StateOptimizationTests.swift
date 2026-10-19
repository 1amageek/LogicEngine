import Testing
import Synchronization
import LogicIR
import LogicKernelCore
import LogicSynthesis
import LogicProofProbeSupport
import LogicOptimizationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct StateOptimizationTests {
    private typealias F = LogicEquivalenceContractProbe
    private typealias O = LogicOptimizationContractProbe
    @Test func randomizedGraphsPreserveEveryLiveOriginAndProveEquivalent() throws {
        for seed in 1...150 {
            var context = try LogicProofContractProbe.context()
            let graph = try O.fixture(seed: UInt64(seed), context: &context)
            let candidate = try O.verify(graph, inputs: 3, outputs: 3, context: &context)
            #expect(candidate.statistics.resultNodes <= candidate.statistics.sourceNodes)
        }
    }
    @Test func allPrimitiveOpcodesAndConstantIdentitiesPreserveTruth() throws {
        var identityContext = try LogicProofContractProbe.context()
        let identities = try O.identities(context: &identityContext)
        let normalized = try O.verify(identities, inputs: 2, outputs: 14, context: &identityContext)
        #expect(normalized.design.nodeCount == 6)
        #expect(normalized.statistics.constantFolds == 6)
        #expect(normalized.statistics.commonSubexpressions >= 1)
        for operation: BitOperation in [.buffer,.invert,.and,.or,.xor,.select] {
            var context = try LogicProofContractProbe.context()
            let graph = try F.bit(operation, context: &context)
            _ = try O.verify(graph, inputs: operation.operandCount, outputs: 1, context: &context)
        }
    }
    @Test func stateControlInitialRangeAndPortIdentitySurvive() throws {
        for latch in [false,true] { for initial: Bool? in [nil,false,true] { for synchronous in [false,true] {
            if latch && synchronous { continue }
            var context = try LogicProofContractProbe.context()
            let graph = try F.state(latch: latch, loweredEnable: !latch, synchronousReset: synchronous, initial: initial, context: &context)
            let candidate = try O.verify(graph, inputs: 4, outputs: 1, context: &context)
            graph.withTables { _, _, ports, _, states, _ in
                candidate.design.withTables { _, _, resultPorts, _, resultStates, _ in
                    #expect(states.count == resultStates.count)
                    for index in states.indices { #expect(states[index].id == resultStates[index].id); #expect(states[index].initialValue == resultStates[index].initialValue) }
                    #expect(ports.count == resultPorts.count)
                    for index in ports.indices { #expect(ports[index].id == resultPorts[index].id); #expect(ports[index].direction == resultPorts[index].direction); #expect(ports[index].bits.count == resultPorts[index].bits.count) }
                }
            }
        } } }
    }
    @Test func unobservedStateAndInputSurviveWhileControlBuffersDisappear() throws {
        var context = try LogicProofContractProbe.context()
        var builder = try BitLogicBuilder(capacity: .init(nodes: 12, operands: 6, ports: 2, portBits: 5, states: 2), context: &context)
        var inputs: [BitNodeIndex] = []
        for index in 0..<4 { inputs.append(try builder.addNode(id: F.id(UInt64(index + 1)), operation: .input, context: &context)) }
        let q0 = try builder.addNode(id: F.id(5), operation: .state(.init(0)), context: &context)
        _ = try builder.addNode(id: F.id(6), operation: .state(.init(1)), context: &context)
        var controls: [BitNodeIndex] = []
        for index in 0..<4 { controls.append(try builder.addNode(id: F.id(UInt64(index + 7)), operation: .buffer, inputs: [inputs[index]], context: &context)) }
        let zero = try builder.addNode(id: F.id(11), operation: .constant(false), context: &context)
        _ = try builder.addNode(id: F.id(12), operation: .xor, inputs: [inputs[0],inputs[2]], context: &context)
        let reset = BitReset(signal: controls[3], activeHigh: false, value: false, kind: .asynchronous)
        _ = try builder.addState(.init(id: F.id(30), next: controls[0], control: .flipFlop(clock: controls[1], edge: .falling, enable: controls[2], reset: reset)), context: &context)
        _ = try builder.addState(.init(id: F.id(31), next: zero, control: .flipFlop(clock: controls[1], edge: .falling, enable: nil, reset: reset), initialValue: true), context: &context)
        try builder.addPort(id: F.id(40), direction: .input, bits: inputs, context: &context)
        try builder.addPort(id: F.id(41), direction: .output, bits: [q0], context: &context)
        let source = try builder.finish(context: &context)
        let candidate = try O.verify(source, inputs: 4, outputs: 1, context: &context)
        #expect(candidate.design.stateCount == 2)
        #expect(candidate.design.nodeCount == 7)
        #expect(candidate.withOrigins { $0[11].destination == nil && $0[5].destination != nil })
    }
    @Test func deadNodesAreExplicitAndRepeatedRunsIgnoreEntityNames() throws {
        var context = try LogicProofContractProbe.context()
        let a = try O.fixture(seed: 9, context: &context)
        let b = try O.fixture(seed: 9, reversedIDs: true, context: &context)
        let ca = try O.verify(a, inputs: 3, outputs: 3, context: &context)
        let cb = try O.verify(b, inputs: 3, outputs: 3, context: &context)
        let repeated = try NativeLogicOptimizer().optimize(a, context: &context)
        #expect(ca.statistics == cb.statistics)
        #expect(ca.statistics == repeated.statistics)
        #expect(ca.statistics.removedNodes > 0)
        #expect(ca.withOrigins { origins in
            var dead = false; for index in origins.indices { if origins[index].destination == nil { dead = true } }; return dead
        })
        for mask in 0..<8 {
            let inputs = [mask & 1 != 0, mask & 2 != 0, mask & 4 != 0]
            #expect(O.values(ca.design, inputs: inputs) == O.values(cb.design, inputs: inputs))
            #expect(O.values(ca.design, inputs: inputs) == O.values(repeated.design, inputs: inputs))
        }
    }
    @Test func forwardReferencesAndDeclarationOrderDoNotChangeMeaningOrDepth() throws {
        var context = try LogicProofContractProbe.context()
        var results: [BitLogicDesign] = []
        for forward in [false,true] {
            var builder = try BitLogicBuilder(capacity: .init(nodes: 3, operands: 2, ports: 2, portBits: 2, states: 0), context: &context)
            let x = try builder.addNode(id: F.id(50), operation: .input, context: &context)
            let output: BitNodeIndex
            if forward {
                output = try builder.addNode(id: F.id(1), operation: .and, inputs: [x,.init(2)], context: &context)
                _ = try builder.addNode(id: F.id(100), operation: .constant(true), context: &context)
            } else {
                let one = try builder.addNode(id: F.id(100), operation: .constant(true), context: &context)
                output = try builder.addNode(id: F.id(1), operation: .and, inputs: [x,one], context: &context)
            }
            try builder.addPort(id: F.id(200), direction: .input, bits: [x], context: &context)
            try builder.addPort(id: F.id(201), direction: .output, bits: [output], context: &context)
            let graph = try builder.finish(context: &context)
            results.append(try O.verify(graph, inputs: 1, outputs: 1, context: &context).design)
        }
        #expect(results[0].nodeCount == 1 && results[1].nodeCount == 1)
        for value in [false,true] { #expect(O.values(results[0], inputs: [value]) == O.values(results[1], inputs: [value])) }
    }
    @Test func successReleasesWorkspaceAndRetainsOnlyPublishedPayload() throws {
        var sourceContext = try LogicProofContractProbe.context()
        let source = try O.fixture(seed: 9, context: &sourceContext)
        var context = try LogicProofContractProbe.context()
        let candidate = try NativeLogicOptimizer().optimize(source, context: &context)
        let graph = candidate.design
        let expected = graph.nodeCount * (MemoryLayout<BitLogicNode>.stride + MemoryLayout<BitNodeIndex>.stride)
            + graph.operandCount * MemoryLayout<BitNodeIndex>.stride
            + graph.portCount * MemoryLayout<BitLogicPort>.stride
            + graph.portBitCount * MemoryLayout<BitNodeIndex>.stride
            + graph.stateCount * MemoryLayout<BitLogicState>.stride
            + source.nodeCount * MemoryLayout<LogicOptimizationOrigin>.stride
            + MemoryLayout<(BitLogicDesign, BitLogicDesign, [LogicOptimizationOrigin], LogicOptimizationStatistics)>.stride
        #expect(context.usage[.managedStorageBytes] == UInt64(expected))
        #expect(context.usage.peakManagedStorageBytes > UInt64(expected))
    }
    @Test func sourceFrontendLoweringOptimizationAndProofCompose() throws {
        var context = try LogicProofContractProbe.context()
        try O.sourceIntegration(context: &context)
        try O.sequentialSourceIntegration(context: &context)
    }
    private final class Interrupt: LogicRunControlling {
        private let remaining: Mutex<Int>
        private let failure: LogicKernelError
        init(after: Int, failure: LogicKernelError) { remaining = Mutex(after); self.failure = failure }
        func checkpoint() throws(LogicKernelError) {
            let stop = remaining.withLock { value in value -= 1; return value < 0 }
            if stop { throw failure }
        }
    }
    @Test func cumulativeWorkLimitRemainsAResourceFailure() throws {
        var sourceContext = try LogicProofContractProbe.context()
        let graph = try O.fixture(seed: 1, context: &sourceContext)
        for work: UInt64 in [1,30,70] {
            var limits: [LogicResource: UInt64] = [:]
            for resource in LogicResource.allCases { limits[resource] = resource == .workUnits ? work : 100_000_000 }
            var context = LogicKernelContext(limits: try .init(maximums: limits), control: LogicProofContractProbe.Control())
            do { _ = try NativeLogicOptimizer().optimize(graph, context: &context); Issue.record("Work limit published a candidate") }
            catch let error as LogicKernelError {
                if case .resourceLimit(let resource, _, _) = error { #expect(resource == .workUnits) }
                else { Issue.record("Wrong work failure") }
            }
            #expect(context.usage[.managedStorageBytes] == 0)
        }
    }
    @Test func cancellationDeadlineAndStorageLimitsDoNotPublishCandidates() throws {
        var sourceContext = try LogicProofContractProbe.context()
        let graph = try O.fixture(seed: 1, context: &sourceContext)
        for failure: LogicKernelError in [.cancelled,.deadlineExceeded] {
            for after in [0,5,30] {
                var context = try LogicProofContractProbe.context(control: Interrupt(after: after, failure: failure))
                do {
                    _ = try NativeLogicOptimizer().optimize(graph, context: &context)
                    Issue.record("Interrupted optimization published a candidate")
                } catch let error as LogicKernelError { #expect(error == failure) }
                #expect(context.usage[.managedStorageBytes] == 0)
            }
        }
        var limited = try LogicProofContractProbe.context(limit: 1)
        do { _ = try NativeLogicOptimizer().optimize(graph, context: &limited); Issue.record("Storage limit accepted") }
        catch let error as LogicKernelError { if case .resourceLimit = error {} else { Issue.record("Wrong limit failure") } }
        #expect(limited.usage[.managedStorageBytes] == 0)
    }
}
