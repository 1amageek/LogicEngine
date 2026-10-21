import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
@testable import LogicEngineRuntime
import LogicKernelCore
import Synchronization
import Testing
import TimingCore

@Suite(.timeLimit(.minutes(1)))
struct ControlledTimingDigestCostTests {
    private enum Failure: Error, Equatable { case work, storage, cancelled }
    private struct Offer: Sendable, Equatable {
        let kind: LibertySourceStorageKind
        let bytes: UInt64
    }
    private final class RecordingResources: LibertySourceResourceAccounting {
        struct State: Sendable {
            var work: UInt64 = 0
            var live: UInt64 = 0
            var temporary: UInt64 = 0
            var retained: UInt64 = 0
            var attempts: [Offer] = []
            var cancelled = false
            var callbacksAfterCancellation = 0
        }
        private let state = Mutex(State())
        private let maximumWork: UInt64
        private let maximumTemporary: UInt64
        private let maximumLive: UInt64
        private let cancelAfterWork: Bool
        private let cancelAfterReservation: Int?
        init(maximumWork: UInt64 = .max, maximumTemporary: UInt64 = .max,
             maximumLive: UInt64 = .max, cancelAfterWork: Bool = false,
             cancelAfterReservation: Int? = nil) {
            self.maximumWork = maximumWork; self.maximumTemporary = maximumTemporary
            self.maximumLive = maximumLive; self.cancelAfterWork = cancelAfterWork
            self.cancelAfterReservation = cancelAfterReservation
        }
        var snapshot: State { state.withLock { $0 } }
        func check() throws {
            if state.withLock({ $0.cancelled }) { throw Failure.cancelled }
        }
        func chargeWork(_ amount: UInt64) throws {
            try state.withLock { value in
                if value.cancelled {
                    value.callbacksAfterCancellation += 1
                    throw Failure.cancelled
                }
                let next = value.work.addingReportingOverflow(amount)
                guard !next.overflow, next.partialValue <= maximumWork else { throw Failure.work }
                value.work = next.partialValue
                if cancelAfterWork { value.cancelled = true }
            }
        }
        func reserveStorage(kind: LibertySourceStorageKind, byteCount: UInt64) throws
            -> LibertySourceStorageReservation {
            try state.withLock { value in
                if value.cancelled {
                    value.callbacksAfterCancellation += 1
                    throw Failure.cancelled
                }
                value.attempts.append(.init(kind: kind, bytes: byteCount))
                let next = value.live.addingReportingOverflow(byteCount)
                let temporary = value.temporary.addingReportingOverflow(kind == .temporaryBytes ? byteCount : 0)
                guard !next.overflow, !temporary.overflow,
                      next.partialValue <= maximumLive, temporary.partialValue <= maximumTemporary else {
                    throw Failure.storage
                }
                value.live = next.partialValue; value.temporary = temporary.partialValue
                if kind == .liveOwnedBytes { value.retained += byteCount }
                if cancelAfterReservation == value.attempts.count { value.cancelled = true }
            }
            return .init(kind: kind, byteCount: byteCount) {
                self.state.withLock {
                    $0.live -= byteCount
                    if kind == .temporaryBytes { $0.temporary -= byteCount }
                    else { $0.retained -= byteCount }
                }
            }
        }
    }

    @Test(arguments: [0, 3, 129])
    func digestParityAndCopiedOwnerKeepOnlyTheRetainedResult(_ count: Int) throws {
        let data = Data((0..<count).map { UInt8($0 % 256) })
        let expected = try SHA256ContentDigester().digest(data: data, using: .sha256)
        let copyCost = try SHA256ContentDigester().foundationDataCopyCost(byteCount: UInt64(data.count))
        let hashCost = try SHA256ContentDigester.managedCost(byteCount: UInt64(data.count))
        let resources = RecordingResources()
        var anchor: LibertySourceStorageReservation?
        do {
            let result = try NativeLogicSynthesisEngine.controlledTimingDesignDigest(data, resources: resources)
            #expect(result.value == expected)
            let actual = resources.snapshot
            #expect(actual.work == copyCost.workUnits + hashCost.workUnits)
            #expect(actual.attempts == [
                Offer(kind: .temporaryBytes, bytes: copyCost.temporaryByteCount + hashCost.temporaryByteCount),
                Offer(kind: .liveOwnedBytes, bytes: hashCost.retainedByteCount)
            ])
            #expect(actual.temporary == 0)
            #expect(actual.live == hashCost.retainedByteCount)
            anchor = result.retention
        }
        var retainedCopy = anchor
        anchor = nil
        #expect(resources.snapshot.retained == hashCost.retainedByteCount)
        withExtendedLifetime(retainedCopy) {}
        retainedCopy = nil
        #expect(resources.snapshot.live == 0)
    }

    @Test func workRefusalHappensBeforeAnyStorageReservation() throws {
        let data = Data("digest work refusal".utf8)
        let cost = try NativeLogicSynthesisEngine.controlledTimingDesignDigestCost(byteCount: UInt64(data.count))
        let resources = RecordingResources(maximumWork: cost.workUnits - 1)
        do {
            _ = try NativeLogicSynthesisEngine.controlledTimingDesignDigest(data, resources: resources)
            Issue.record("Digest exceeded the original work policy")
        } catch { #expect(error as? Failure == .work) }
        #expect(resources.snapshot.work == 0)
        #expect(resources.snapshot.attempts.isEmpty)
        #expect(resources.snapshot.live == 0)
    }

    @Test(arguments: [false, true])
    func temporaryAndSimultaneousRetainedQuotaRefuseWithoutPublishing(_ retainedStage: Bool) throws {
        let data = Data(repeating: 0xa5, count: 129)
        let cost = try NativeLogicSynthesisEngine.controlledTimingDesignDigestCost(byteCount: UInt64(data.count))
        let resources = retainedStage
            ? RecordingResources(maximumLive: cost.temporaryByteCount + cost.retainedByteCount - 1)
            : RecordingResources(maximumTemporary: cost.temporaryByteCount - 1)
        do {
            _ = try NativeLogicSynthesisEngine.controlledTimingDesignDigest(data, resources: resources)
            Issue.record("Digest exceeded the original storage policy")
        } catch { #expect(error as? Failure == .storage) }
        #expect(resources.snapshot.attempts.count == (retainedStage ? 2 : 1))
        #expect(resources.snapshot.work == cost.workUnits)
        #expect(resources.snapshot.live == 0)
    }

    @Test(arguments: [0, 1, 2])
    func callbackCancellationStopsBeforeTheNextReservation(_ stage: Int) throws {
        let resources = RecordingResources(cancelAfterWork: stage == 0,
            cancelAfterReservation: stage == 0 ? nil : stage)
        do {
            _ = try NativeLogicSynthesisEngine.controlledTimingDesignDigest(Data("cancel digest".utf8), resources: resources)
            Issue.record("Cancelled digest operation published a value")
        } catch { #expect(error as? Failure == .cancelled) }
        #expect(resources.snapshot.cancelled)
        #expect(resources.snapshot.attempts.count == stage)
        #expect(resources.snapshot.callbacksAfterCancellation == 0)
        #expect(resources.snapshot.live == 0)
    }

    @Test func originalPhaseImportsPrespentWorkAndRetainsOnlyTheLastCopy() throws {
        let data = Data("original phase digest".utf8)
        let expected = try SHA256ContentDigester().digest(data: data, using: .sha256)
        let cost = try NativeLogicSynthesisEngine.controlledTimingDesignDigestCost(byteCount: UInt64(data.count))
        let limits = ActualCellRuntimeTests().limits()
        let ledger = ControlledReloadTestLedger()
        let resources = LogicReloadResources(control: ledger)
        var context = LogicKernelContext(limits: try limits.kernelLimits(),
            control: ControlledReloadTestControl(), accounting: resources)
        try context.charge(.workUnits, amount: 17)
        var anchor: LibertySourceStorageReservation?
        do {
            let phase = try LogicReloadPhase.make(context: &context, resources: resources)
            let source = try LogicReloadLibertyResources.make(phase: phase)
            let result = try NativeLogicSynthesisEngine.controlledTimingDesignDigest(data, resources: source)
            #expect(result.value == expected)
            try phase.importOnce(into: &context)
            #expect(context.usage[.workUnits] == 17 + cost.workUnits)
            #expect(ledger.snapshot.work == context.usage[.workUnits])
            anchor = result.retention
        }
        var retainedCopy = anchor
        anchor = nil
        #expect(ledger.snapshot.live > 0)
        withExtendedLifetime(retainedCopy) {}
        retainedCopy = nil
        #expect(ledger.snapshot.live == 0 && ledger.snapshot.open == 0)
    }

    @Test func scalarCostPlanningRejectsAddressAndCombinedWorkOverflow() throws {
        do {
            _ = try NativeLogicSynthesisEngine.controlledTimingDesignDigestCost(byteCount: .max)
            Issue.record("Unaddressable digest input was admitted")
        } catch let failure as ContentDigestError {
            switch failure {
            case .byteCountOverflow: break
            default: Issue.record("Unexpected public digest planning cause: \(failure)")
            }
        }
        try #require(Int.bitWidth == 64)
        do {
            _ = try NativeLogicSynthesisEngine.controlledTimingDesignDigestCost(byteCount: UInt64(Int.max))
            Issue.record("Combined copy/hash work overflow was admitted")
        } catch let failure as LibertySourceError {
            switch failure {
            case .arithmeticOverflow: break
            default: Issue.record("Unexpected aggregate planning cause: \(failure)")
            }
        }
    }
}
