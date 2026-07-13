import Foundation

public struct NativeLogicQualificationRunner: Sendable {
    public let executor: any LogicQualificationExecuting

    public init(executor: any LogicQualificationExecuting) {
        self.executor = executor
    }

    public func evaluate(
        _ suite: LogicQualificationSuite,
        checkedAt: Date = Date()
    ) async throws -> LogicQualificationReport {
        try suite.validate()
        var evaluations: [LogicQualificationCaseEvaluation] = []
        for qualificationCase in suite.cases.sorted(by: { $0.caseID < $1.caseID }) {
            let observation = try await executor.execute(qualificationCase.request)
            let expected = qualificationCase.expectation
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
            evaluations.append(LogicQualificationCaseEvaluation(
                caseID: qualificationCase.caseID,
                matched: mismatches.isEmpty,
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
        return LogicQualificationReport(
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
