import Foundation
import LogicEngineCore
import LogicEvidence
import Testing

@Suite("Logic evidence contracts")
struct EvidenceTests {
    @Test("corpus outcome is derived from passive case mismatches")
    func corpusOutcomeIsDerived() throws {
        let report = report()
        #expect(report.state == .corpusChecked)
        #expect(report.corpusPassed)
        try report.validate()

        let encoded = try JSONEncoder().encode(report)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var evaluations = try #require(object["evaluations"] as? [[String: Any]])
        evaluations[0]["matched"] = false
        object["evaluations"] = evaluations
        let decoded = try JSONDecoder().decode(
            LogicEvidenceReport.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
        #expect(decoded.corpusPassed)
    }

    @Test("oracle correlation is derived from identities and raw mismatches")
    func oracleCorrelationIsDerived() throws {
        let report = report()
        let oracle = try loadOracle()
        let correlator = NativeLogicEvidenceOracleCorrelator()
        let correlation = try correlator.correlate(nativeReport: report, oracle: oracle)
        let correlated = report.includingOracleCorrelation(correlation)
        #expect(correlation.matched && correlation.independenceVerified)
        #expect(correlated.state == .oracleCorrelated && correlated.oraclePassed)
        try correlated.validate()

        let selfOracle = LogicEvidenceOracleObservationSet(
            oracleImplementationID: report.implementationID,
            oracleImplementationVersion: "1", observations: oracle.observations
        )
        let rejected = try correlator.correlate(nativeReport: report, oracle: selfOracle)
        #expect(!rejected.isUsableForPromotion)
        #expect(rejected.mismatches.contains("oracle_not_independent"))

        var changed = oracle
        changed.observations[0].observation.diagnosticCodes = ["different"]
        let mismatch = try correlator.correlate(nativeReport: report, oracle: changed)
        #expect(!mismatch.isUsableForPromotion)
        #expect(mismatch.mismatches.contains("diagnostic_mismatch:simulation-and-gate"))
    }

    @Test("a report cannot claim oracle correlation without complete independent coverage")
    func forgedOracleStateIsRejected() throws {
        var forged = report()
        forged.state = .oracleCorrelated
        #expect(throws: LogicEvidenceError.self) { try forged.validate() }
    }

    @Test("a corpus mismatch remains reviewable raw evidence and cannot claim promotion")
    func corpusMismatchFailsClosedWithStructuredBlockers() throws {
        var mismatch = report()
        mismatch.evaluations[0].observedStatus = .blocked
        mismatch.evaluations[0].mismatches = ["status expected completed observed blocked"]
        mismatch.blockers = ["simulation-and-gate:status mismatch"]
        mismatch.limitations = mismatch.evaluations[0].mismatches
        #expect(!mismatch.corpusPassed)
        #expect(throws: LogicEvidenceError.self) { try mismatch.validate() }
        mismatch.state = .unassessed
        try mismatch.validate()
        #expect(mismatch.blockers == ["simulation-and-gate:status mismatch"])
        let correlation = try NativeLogicEvidenceOracleCorrelator().correlate(
            nativeReport: mismatch, oracle: loadOracle()
        )
        #expect(!mismatch.includingOracleCorrelation(correlation).oraclePassed)
    }

    private func report() -> LogicEvidenceReport {
        let simulationCases = ["simulation-and-gate", "simulation-signed-arithmetic", "simulation-vector-logical"]
        var evaluations = simulationCases.map {
            LogicEvidenceCaseEvaluation(caseID: $0, observedStatus: .completed,
                observedDiagnosticCodes: ["logic.simulation.completed"],
                observedArtifactIDs: ["logic-simulation-report", "logic-waveform"], mismatches: [])
        }
        evaluations.append(LogicEvidenceCaseEvaluation(caseID: "synthesis-and-gate", observedStatus: .completed,
            observedDiagnosticCodes: ["LOGIC_EQUIVALENCE_REQUIRED", "LOGIC_SYNTHESIS_COMPLETED"],
            observedArtifactIDs: ["logic-equivalence-request", "logic-synthesis-provenance", "mapped-design"], mismatches: []))
        return LogicEvidenceReport(suiteID: "passive-report", implementationID: "native-observations",
            implementationVersion: "1", state: .corpusChecked, evaluations: evaluations,
            checkedAt: Date(timeIntervalSince1970: 1))
    }

    private func loadOracle() throws -> LogicEvidenceOracleObservationSet {
        let url = try #require(Bundle.module.url(forResource: "logic-evidence-oracle-v1",
            withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(LogicEvidenceOracleObservationSet.self, from: Data(contentsOf: url))
    }
}
