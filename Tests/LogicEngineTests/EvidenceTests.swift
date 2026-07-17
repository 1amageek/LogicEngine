import Foundation
import LogicEngineCore
import LogicEvidence
import Testing

@Suite("Logic evidence contracts")
struct EvidenceTests {
    @Test("retained suite decodes as an agent-operable corpus")
    func evidenceFixtureDecodes() throws {
        let suite = try loadSuite()
        try suite.validate()
        #expect(suite.cases.count == 4)
    }

    @Test("corpus outcome is derived from case mismatches")
    func corpusOutcomeIsDerived() async throws {
        let suite = try loadSuite()
        let report = try await NativeLogicEvidenceRunner(
            executor: FixtureObservationExecutor()
        ).evaluate(suite, checkedAt: Date(timeIntervalSince1970: 1))

        #expect(report.state == .corpusChecked)
        #expect(report.corpusPassed)
        #expect(report.evaluations.filter { !$0.matched }.isEmpty)
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
    func oracleCorrelationIsDerived() async throws {
        let report = try await NativeLogicEvidenceRunner(
            executor: FixtureObservationExecutor()
        ).evaluate(try loadSuite(), checkedAt: Date(timeIntervalSince1970: 1))
        let oracle = try loadOracle()
        let correlation = try NativeLogicEvidenceOracleCorrelator().correlate(
            nativeReport: report,
            oracle: oracle
        )
        let correlated = report.includingOracleCorrelation(correlation)

        #expect(correlation.matched)
        #expect(correlation.independenceVerified)
        #expect(correlated.state == .oracleCorrelated)
        #expect(correlated.oraclePassed)
        try correlated.validate()

        let selfOracle = LogicEvidenceOracleObservationSet(
            oracleImplementationID: report.implementationID,
            oracleImplementationVersion: "1",
            observations: oracle.observations
        )
        let rejected = try NativeLogicEvidenceOracleCorrelator().correlate(
            nativeReport: report,
            oracle: selfOracle
        )
        #expect(!rejected.independenceVerified)
        #expect(!rejected.isUsableForPromotion)
        #expect(rejected.mismatches.contains("oracle_not_independent"))
    }

    @Test("duplicate corpus case identities fail validation")
    func duplicateCaseIdentityIsRejected() throws {
        var suite = try loadSuite()
        suite.cases.append(try #require(suite.cases.first))

        #expect(throws: LogicEvidenceError.duplicateCase(suite.cases[0].caseID)) {
            try suite.validate()
        }
    }

    @Test("unbounded corpus cases remain executable raw evidence")
    func unboundedCorpusExecutes() async throws {
        let suite = try loadUnboundedSuite()
        let report = try await NativeLogicEvidenceRunner(
            executor: ExpectedObservationExecutor(suite: suite)
        ).evaluate(suite, checkedAt: Date(timeIntervalSince1970: 1))

        #expect(report.state == .corpusChecked)
        #expect(report.evaluations.count == suite.cases.count)
        #expect(report.corpusPassed)
        try report.validate()
    }

    @Test("a report cannot claim oracle correlation without complete independent coverage")
    func forgedOracleStateIsRejected() throws {
        let report = LogicEvidenceReport(
            suiteID: "suite",
            implementationID: "native",
            implementationVersion: "1",
            state: .oracleCorrelated,
            evaluations: [LogicEvidenceCaseEvaluation(
                caseID: "case",
                observedStatus: .completed,
                observedDiagnosticCodes: [],
                observedArtifactIDs: [],
                mismatches: []
            )]
        )

        #expect(throws: LogicEvidenceError.self) {
            try report.validate()
        }
    }

    @Test("a corpus mismatch remains reviewable raw evidence and cannot claim promotion")
    func corpusMismatchFailsClosedWithStructuredBlockers() async throws {
        let suite = try loadSuite()
        let report = try await NativeLogicEvidenceRunner(
            executor: MismatchingObservationExecutor()
        ).evaluate(suite, checkedAt: Date(timeIntervalSince1970: 2))

        #expect(report.state == .unassessed)
        #expect(!report.corpusPassed)
        #expect(report.blockers.count == suite.cases.count)
        #expect(report.limitations.contains { $0.contains("status expected") })
        try report.validate()
    }

    private func loadSuite() throws -> LogicEvidenceSuite {
        try JSONDecoder().decode(
            LogicEvidenceSuite.self,
            from: Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-evidence-suite"))
        )
    }

    private func loadOracle() throws -> LogicEvidenceOracleObservationSet {
        try JSONDecoder().decode(
            LogicEvidenceOracleObservationSet.self,
            from: Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-evidence-oracle-v1"))
        )
    }

    private func loadUnboundedSuite() throws -> LogicEvidenceSuite {
        try JSONDecoder().decode(
            LogicEvidenceSuite.self,
            from: Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-unbounded-evidence-suite"))
        )
    }
}

private struct MismatchingObservationExecutor: LogicEvidenceExecuting {
    func execute(_ request: LogicEvidenceRequest) async throws -> LogicEvidenceObservation {
        LogicEvidenceObservation(status: .blocked)
    }
}

private struct ExpectedObservationExecutor: LogicEvidenceExecuting {
    let observations: [String: LogicEvidenceObservation]

    init(suite: LogicEvidenceSuite) {
        observations = Dictionary(uniqueKeysWithValues: suite.cases.map {
            ($0.request.runID, LogicEvidenceObservation(
                status: $0.expectation.expectedStatus,
                diagnosticCodes: $0.expectation.requiredDiagnosticCodes
            ))
        })
    }

    func execute(_ request: LogicEvidenceRequest) async throws -> LogicEvidenceObservation {
        guard let observation = observations[request.runID] else {
            throw LogicEvidenceError.unsupportedRequest(request.runID)
        }
        return observation
    }
}

private struct FixtureObservationExecutor: LogicEvidenceExecuting {
    func execute(
        _ request: LogicEvidenceRequest
    ) async throws -> LogicEvidenceObservation {
        switch request.runID {
        case "logic-evidence-simulation":
            return LogicEvidenceObservation(
                status: .completed,
                diagnosticCodes: ["logic.simulation.completed"],
                artifactIDs: ["logic-simulation-report", "logic-waveform"]
            )
        case "logic-evidence-synthesis":
            return LogicEvidenceObservation(
                status: .completed,
                diagnosticCodes: ["LOGIC_EQUIVALENCE_REQUIRED", "LOGIC_SYNTHESIS_COMPLETED"],
                artifactIDs: ["logic-equivalence-request", "logic-synthesis-provenance", "mapped-design"]
            )
        case "logic-evidence-signed-arithmetic", "logic-evidence-vector-logical":
            return LogicEvidenceObservation(
                status: .completed,
                diagnosticCodes: ["logic.simulation.completed"],
                artifactIDs: ["logic-simulation-report", "logic-waveform"]
            )
        default:
            throw LogicEvidenceError.unsupportedRequest(request.runID)
        }
    }
}
