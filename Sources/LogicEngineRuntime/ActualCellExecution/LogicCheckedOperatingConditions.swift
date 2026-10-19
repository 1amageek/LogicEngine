/// Checked host premises for one actual mapped graph, separate from circuit proof and electrical trust.
public struct LogicCheckedOperatingConditions: Sendable {
    public let receipt: LogicOperatingConditionReceipt
    private let compilation: LogicLibraryCompilation

    internal init(receipt: LogicOperatingConditionReceipt, compilation: LogicLibraryCompilation) {
        self.receipt = receipt; self.compilation = compilation
    }
}
