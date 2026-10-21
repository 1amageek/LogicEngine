import LogicKernelCore
import PDKDiscovery

/// Keep this anchor with every extracted/shared value of the controlled load.
public struct LogicReloadRetention: Sendable {
    private let receipt: PDKDecodedDocument<LogicSynthesisReceipt>
    private let request: PDKDecodedDocument<LogicSynthesisRequest>
    private let parts: LogicReloadRetainedParts
    private let metadata: LogicKernelRetention

    internal init(receipt: PDKDecodedDocument<LogicSynthesisReceipt>,
        request: PDKDecodedDocument<LogicSynthesisRequest>, parts: LogicReloadRetainedParts,
        metadata: LogicKernelRetention) {
        self.receipt = receipt; self.request = request; self.parts = parts; self.metadata = metadata
    }
}
