import Testing
import LogicOptimizationProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct TechnologyMappingTests {
    @Test func mappingCannotManufactureStartupFromInitialMetadata() throws {
        var run = try LogicProofContractProbe.context()
        for latch in [false, true] {
            let source = try LogicEquivalenceContractProbe.state(latch: latch, initial: false, context: &run)
            let library = try TechnologyMappingContractProbe.library([
                TechnologyMappingContractProbe.cell(.nand, id: 100, area: 1, context: &run),
                TechnologyMappingContractProbe.sequentialCell(latch: latch, asynchronous: true, context: &run)], context: &run)
            #expect(throws: LogicKernelError.self) {
                try NativeLogicTechnologyMapper().map(source, library: library,
                    policy: TechnologyMappingContractProbe.policy(), context: &run)
            }
        }
    }
    @Test func startupDemandsAndActualDualTieOutputsAreIndependentlyChecked() throws { try TechnologyMappingContractProbe.startupAndPhysicalTies() }
    @Test func actualNANDAndNORCoverEveryPrimitive() throws { try TechnologyMappingContractProbe.combinational() }
    @Test func pinPermutationAndEveryPhysicalOutput() throws { try TechnologyMappingContractProbe.permutationsAndMultiOutput() }
    @Test func exactFFLatchEnableSyncAsyncAndInitialState() throws { try TechnologyMappingContractProbe.sequential() }
    @Test func sourceWidthToActualCellProof() throws { try TechnologyMappingContractProbe.sourceIntegration() }
}

import Synchronization
import LogicIR
import LogicKernelCore
import LogicSynthesis
import LogicProof
import LogicProofProbeSupport

extension TechnologyMappingTests {
    @Test func deterministicAreaDepthStableIDAndConnectionTopology() throws { try TechnologyMappingContractProbe.stableSelectionAndTopology() }
    @Test func wrongStateAndMissingFunctionAreExplicitRefusals() throws { try TechnologyMappingContractProbe.rejectWrongStateControls() }
    @Test func tamperedActualPinAndFunctionHaveReplayedCounterexamples() throws { try TechnologyMappingContractProbe.tamperedPinsFailIndependentProof() }
    private final class Interrupt: LogicRunControlling {
        private let remaining: Mutex<Int>
        private let error: LogicKernelError
        init(after: Int, error: LogicKernelError) { remaining = Mutex(after); self.error = error }
        func checkpoint() throws(LogicKernelError) {
            if remaining.withLock({ $0 -= 1; return $0 < 0 }) { throw error }
        }
    }
    @Test func cancellationDeadlineAndCumulativeBudgetsCannotPublish() throws {
        var preparation = try LogicProofContractProbe.context()
        let source = try LogicEquivalenceContractProbe.bit(.xor,context:&preparation)
        let library = try TechnologyMappingContractProbe.library([TechnologyMappingContractProbe.cell(.nand,id:100,area:1,context:&preparation)],context:&preparation)
        let mapper: any LogicTechnologyMapping = NativeLogicTechnologyMapper()
        let policy = try TechnologyMappingContractProbe.policy()
        for expected: LogicKernelError in [.cancelled,.deadlineExceeded] {
            for after in [0,50,500,2000] {
                var context = try LogicProofContractProbe.context(control:Interrupt(after:after,error:expected))
                do { _ = try mapper.map(source,library:library,policy:policy,context:&context); Issue.record("Interrupted mapping published") }
                catch { #expect(error == expected) }
                #expect(context.usage[.managedStorageBytes] == 0)
            }
        }
        for (resource, limit): (LogicResource,UInt64) in [(.workUnits,10),(.workUnits,300),(.managedStorageBytes,1),(.allocationBytes,1)] {
            var maximums: [LogicResource:UInt64] = [:]
            for r in LogicResource.allCases { maximums[r] = r == resource ? limit : 100_000_000 }
            var context = LogicKernelContext(limits:try .init(maximums:maximums),control:LogicProofContractProbe.Control())
            do { _ = try mapper.map(source,library:library,policy:policy,context:&context); Issue.record("Limited mapping published") }
            catch {
                guard case .resourceLimit(let actual,_,_) = error else { Issue.record("Wrong resource failure"); continue }
                #expect(actual == resource)
            }
            #expect(context.usage[.managedStorageBytes] == 0)
        }
        #expect(throws: LogicKernelError.self) { try TechnologyMappingContractProbe.policy(inputs:7) }
        #expect(throws: LogicKernelError.self) { try TechnologyMappingContractProbe.policy(cuts:0) }
        var overflow = try LogicProofContractProbe.context()
        #expect(throws: LogicKernelError.self) { try mapper.map(source,library:library,policy:TechnologyMappingContractProbe.policy(cuts:Int.max),context:&overflow) }
    }
}

extension TechnologyMappingTests {
    @Test func sixInputTruthTableBoundaryAbsorbsUnmappedInternalNodes() throws { try TechnologyMappingContractProbe.sixInputCutAndAbsorbedNodes() }
    @Test func publishedStorageExcludesTemporaryGraphAndWorkspaces() throws {
        var preparation = try LogicProofContractProbe.context()
        let source = try LogicEquivalenceContractProbe.bit(context:&preparation)
        let library = try TechnologyMappingContractProbe.library([TechnologyMappingContractProbe.cell(.nand,id:100,area:1,context:&preparation)],context:&preparation)
        var context = try LogicProofContractProbe.context()
        let result = try NativeLogicTechnologyMapper().map(source,library:library,policy:TechnologyMappingContractProbe.policy(),context:&context)
        let mapped = result.design
        let expected = mapped.netCount * MemoryLayout<MappedGateNet>.stride
            + mapped.instanceCount * MemoryLayout<MappedGateInstance>.stride
            + mapped.pinConnectionCount * MemoryLayout<MappedNetIndex>.stride
            + mapped.portCount * MemoryLayout<MappedGatePort>.stride
            + mapped.portBitCount * MemoryLayout<MappedNetIndex>.stride
            + (mapped.netCount + mapped.instanceCount) * MemoryLayout<MappedEvaluationStep>.stride
            + MemoryLayout<(LogicTechnologyLibrary,[MappedGateNet],[MappedGateInstance],[MappedNetIndex],[MappedGatePort],[MappedNetIndex],[MappedEvaluationStep],Int)>.stride
            + source.nodeCount * MemoryLayout<LogicMappingOrigin>.stride
            + MemoryLayout<(BitLogicDesign,MappedGateDesign,LogicMappingStatistics,[LogicMappingOrigin])>.stride
        #expect(context.usage[.managedStorageBytes] == UInt64(expected))
        #expect(context.usage.peakManagedStorageBytes > UInt64(expected))
        var maximums: [LogicResource:UInt64] = [:]
        for r in LogicResource.allCases { maximums[r] = r == .outputBytes ? 1 : 100_000_000 }
        var bounded = LogicKernelContext(limits:try .init(maximums:maximums),control:LogicProofContractProbe.Control())
        do { _ = try NativeLogicTechnologyMapper().map(source,library:library,policy:TechnologyMappingContractProbe.policy(),context:&bounded); Issue.record("Output-limited mapping published") }
        catch { guard case .resourceLimit(let resource,_,_) = error else { Issue.record("Wrong output failure"); return }; #expect(resource == .outputBytes) }
    }
}

extension TechnologyMappingTests {
    @Test func sourceMultiBitAsyncPresetAndLowGateLatchProveInductively() throws { try TechnologyMappingContractProbe.sourceStateIntegration() }
}

extension TechnologyMappingTests {
    @Test func repeatedPhysicalPinsDoNotConsumeDistinctCutInputs() throws {
        var context = try LogicProofContractProbe.context()
        let reference = try LogicEquivalenceContractProbe.bit(.invert,context:&context)
        let library = try TechnologyMappingContractProbe.library([TechnologyMappingContractProbe.cell(.nand,id:100,area:1,context:&context)],context:&context)
        let result = try NativeLogicTechnologyMapper().map(reference,library:library,policy:TechnologyMappingContractProbe.policy(inputs:1),context:&context)
        #expect(result.design.instanceCount == 1)
        let problem = try LogicEquivalenceContractProbe.problem(.bit(reference),.mapped(result.design),inputs:1,context:&context)
        guard case .equivalent = try NativeLogicEquivalenceChecker().check(problem,context:&context) else { Issue.record("Repeated-pin inverter was not proved"); return }
    }
}
