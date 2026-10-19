import LogicKernelCore

public struct LogicBitCorrespondence: Sendable, Equatable {
    public let reference: Int
    public let candidate: Int
    public init(reference: Int, candidate: Int) throws(LogicKernelError) {
        guard reference >= 0, candidate >= 0 else { throw .invalidInput("Correspondence ordinals must be nonnegative") }
        self.reference = reference; self.candidate = candidate
    }
}
