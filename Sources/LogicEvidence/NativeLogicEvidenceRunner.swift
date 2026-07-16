import Foundation

public struct NativeLogicEvidenceRunner: Sendable {
    public let executor: any LogicEvidenceExecuting

    public init(executor: any LogicEvidenceExecuting) {
        self.executor = executor
    }

    public func evaluate(
        _ suite: LogicEvidenceSuite,
        checkedAt: Date = Date()
    ) async throws -> LogicEvidenceReport {
        try suite.validate()
        var evaluations: [LogicEvidenceCaseEvaluation] = []
        for evidenceCase in suite.cases.sorted(by: { $0.caseID < $1.caseID }) {
            let observation = try await executor.execute(evidenceCase.request)
            let expected = evidenceCase.expectation
            var mismatches: [String] = []
            if observation.status != expected.expectedStatus {
                mismatches.append(
                    "status expected \(expected.expectedStatus.rawValue) but observed \(observation.status.rawValue)"
                )
            }
            for code in expected.requiredDiagnosticCodes where !observation.diagnosticCodes.contains(code) {
                mismatches.append("required diagnostic missing: \(code)")
            }
            for code in expected.forbiddenDiagnosticCodes where observation.diagnosticCodes.contains(code) {
                mismatches.append("forbidden diagnostic observed: \(code)")
            }
            evaluations.append(LogicEvidenceCaseEvaluation(
                caseID: evidenceCase.caseID,
                observedStatus: observation.status,
                observedDiagnosticCodes: observation.diagnosticCodes,
                observedArtifactIDs: observation.artifactIDs,
                mismatches: mismatches
            ))
        }
        let blockers = evaluations.filter { !$0.matched }.map { "corpus_mismatch:\($0.caseID)" }
        let limitations = evaluations.flatMap { evaluation in
            evaluation.mismatches.map { "\(evaluation.caseID): \($0)" }
        }
        return LogicEvidenceReport(
            suiteID: suite.suiteID,
            implementationID: suite.implementationID,
            implementationVersion: suite.implementationVersion,
            state: evaluations.allSatisfy(\.matched) ? .corpusChecked : .unassessed,
            evaluations: evaluations,
            blockers: blockers,
            limitations: limitations,
            checkedAt: checkedAt
        )
    }
}
