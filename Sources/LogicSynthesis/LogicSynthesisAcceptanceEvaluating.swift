import Foundation

public protocol LogicSynthesisAcceptanceEvaluating: Sendable {
    func evaluate(
        request: LogicSynthesisEquivalenceRequest,
        evidence: LogicSynthesisEquivalenceEvidence
    ) -> LogicSynthesisAcceptanceResult
}
