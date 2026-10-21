import LogicKernelCore
import PDKDiscovery
import Synchronization
import STAEngine
import TimingCore

internal final class LogicReloadState: Sendable {
    let snapshot: LogicReloadSnapshot
    let resources: LogicReloadResources
    let receipt: PDKDecodedDocument<LogicSynthesisReceipt>
    let request: PDKDecodedDocument<LogicSynthesisRequest>
    let metadata: LogicKernelRetention
    let receiptByteCount: UInt64
    let savedTiming: TimingTransformValue<STAExecutionResult>?
    let parts = Mutex(LogicReloadRetainedParts())

    init(snapshot: LogicReloadSnapshot, resources: LogicReloadResources,
        receipt: PDKDecodedDocument<LogicSynthesisReceipt>, request: PDKDecodedDocument<LogicSynthesisRequest>,
        metadata: LogicKernelRetention, receiptByteCount: UInt64, savedTiming: TimingTransformValue<STAExecutionResult>?) {
        self.snapshot = snapshot; self.resources = resources; self.receipt = receipt
        self.request = request; self.metadata = metadata; self.receiptByteCount = receiptByteCount; self.savedTiming = savedTiming
    }

    func retention() -> LogicReloadRetention {
        .init(receipt: receipt, request: request, parts: parts.withLock { $0 }, metadata: metadata)
    }
}
