import LogicIR
import LogicProof
import LogicKernelCore

public struct LogicVerifiedSynthesis: Sendable, LogicMappedOperatingConditionsQualifying {
    public let request: LogicSynthesisRequest
    public let receipt: LogicSynthesisReceipt
    public let original: BitLogicDesign
    public let mapped: MappedGateDesign
    public let problem: LogicEquivalenceProblem
    public let equivalence: CheckedLogicEquivalence
    public let operatingConditions: LogicCheckedOperatingConditions
    private let compilation: LogicLibraryCompilation
    internal init(request: LogicSynthesisRequest, receipt: LogicSynthesisReceipt, original: BitLogicDesign,
                  mapped: MappedGateDesign, problem: LogicEquivalenceProblem, equivalence: CheckedLogicEquivalence,
                  operatingConditions: LogicCheckedOperatingConditions, compilation: LogicLibraryCompilation) {
        self.request = request; self.receipt = receipt; self.original = original; self.mapped = mapped
        self.problem = problem; self.equivalence = equivalence
        self.operatingConditions = operatingConditions; self.compilation = compilation
    }

    public func qualifyOperatingConditions(_ candidate: borrowing MappedGateDesign, context: inout LogicKernelContext)
        throws(LogicOperatingConditionError) -> LogicCheckedOperatingConditions {
        do {
            let corners = try LogicOperatingConditionExpansion.scopes(request, context: &context)
            return try LogicOperatingConditionExpansion.qualify(candidate, compilation: compilation,
                libraryReference: request.library.reference, corners: corners, context: &context)
        } catch let error as LogicOperatingConditionError { throw error }
        catch let error as LogicKernelError { throw .kernel(error) }
        catch { throw .invalidInput(String(describing: error)) }
    }
}
