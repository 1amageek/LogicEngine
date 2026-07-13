import Foundation
import LogicEngineCore
import LogicIR
import LogicQualification
import LogicSimulation
import LogicSynthesis
import Testing
import CircuiteFoundation

@Suite("Logic qualification contracts")
struct QualificationTests {
    @Test("qualification fixture decodes as an agent-operable suite")
    func qualificationFixtureDecodes() throws {
        guard let url = Bundle.module.url(
            forResource: "logic-qualification-suite",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw LogicExecutionError.missingArtifact("logic-qualification-suite.json")
        }
        let suite = try JSONDecoder().decode(
            LogicQualificationSuite.self,
            from: Data(contentsOf: url)
        )
        try suite.validate()
        #expect(suite.cases.count == 4)
    }

    @Test("qualification runner executes the Foundation-native unbounded proof case", .timeLimit(.minutes(1)))
    func unboundedQualificationCaseExecutes() async throws {
        let suiteData = try Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-unbounded-qualification-suite"))
        let decodedSuite = try JSONDecoder().decode(LogicQualificationSuite.self, from: suiteData)
        let (suite, outputDirectory) = try isolatedOutputSuite(decodedSuite)
        defer { removeTemporaryDirectory(outputDirectory) }
        let root = LogicEngineTestFixture.workspaceRootURL()
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let report = try await NativeLogicQualificationRunner(
            executor: NativeLogicQualificationExecutor(
                simulation: NativeLogicSimulationEngine(artifactStore: store),
                synthesis: NativeLogicSynthesisEngine(artifactStore: store),
                unbounded: NativeLogicUnboundedTemporalEquivalenceFoundationEngine(artifactStore: store)
            )
        ).evaluate(suite)
        let oracleData = try Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-unbounded-qualification-oracle-v1"))
        let oracle = try JSONDecoder().decode(
            LogicQualificationOracleObservationSet.self,
            from: oracleData
        )
        let correlated = report.includingOracleCorrelation(
            try NativeLogicQualificationOracleCorrelator().correlate(
                nativeReport: report,
                oracle: oracle
            )
        )

        #expect(report.corpusPassed)
        #expect(correlated.state == .oracleCorrelated)
        #expect(correlated.oraclePassed)
    }

    @Test("unbounded qualification fixtures pass process and release gates")
    func unboundedQualificationPromotesToRelease() async throws {
        let suiteData = try Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-unbounded-qualification-suite"))
        let decodedSuite = try JSONDecoder().decode(LogicQualificationSuite.self, from: suiteData)
        let (suite, outputDirectory) = try isolatedOutputSuite(decodedSuite)
        defer { removeTemporaryDirectory(outputDirectory) }
        let root = LogicEngineTestFixture.workspaceRootURL()
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        var report = try await NativeLogicQualificationRunner(
            executor: NativeLogicQualificationExecutor(
                simulation: NativeLogicSimulationEngine(artifactStore: store),
                synthesis: NativeLogicSynthesisEngine(artifactStore: store),
                unbounded: NativeLogicUnboundedTemporalEquivalenceFoundationEngine(artifactStore: store)
            )
        ).evaluate(suite)
        let oracleData = try Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-unbounded-qualification-oracle-v1"))
        let oracle = try JSONDecoder().decode(LogicQualificationOracleObservationSet.self, from: oracleData)
        report = report.includingOracleCorrelation(
            try NativeLogicQualificationOracleCorrelator().correlate(nativeReport: report, oracle: oracle)
        )
        let processData = try Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-unbounded-qualification-process-evidence"))
        report = try report.includingProcessQualification(
            try JSONDecoder().decode(LogicQualificationProcessEvidence.self, from: processData)
        )
        let approvalData = try Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-unbounded-qualification-release-approval"))
        report = try report.includingReleaseApproval(
            try JSONDecoder().decode(LogicQualificationReleaseApproval.self, from: approvalData)
        )

        try report.validate()
        #expect(report.state == .releaseEligible)
        #expect(report.isReleaseEligible)
    }

    private func isolatedOutputSuite(
        _ suite: LogicQualificationSuite
    ) throws -> (LogicQualificationSuite, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("logic-qualification-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases = suite.cases.map { qualificationCase in
            guard case .unbounded(let request) = qualificationCase.request else {
                return qualificationCase
            }
            let isolatedRequest = LogicUnboundedTemporalEquivalenceFoundationRequest(
                runID: request.runID,
                referenceDesign: request.referenceDesign,
                implementationDesign: request.implementationDesign,
                outputSignals: request.outputSignals,
                valueDomain: request.valueDomain,
                stateSpaceLimit: request.stateSpaceLimit,
                transitionLimit: request.transitionLimit,
                timeoutNanoseconds: request.timeoutNanoseconds,
                clockSignal: request.clockSignal,
                inputs: request.inputs,
                artifactDirectory: directory.path
            )
            return LogicQualificationCase(
                caseID: qualificationCase.caseID,
                request: .unbounded(isolatedRequest),
                expectation: qualificationCase.expectation
            )
        }
        return (
            LogicQualificationSuite(
                suiteID: suite.suiteID,
                implementationID: suite.implementationID,
                implementationVersion: suite.implementationVersion,
                cases: cases,
                schemaVersion: suite.schemaVersion
            ),
            directory
        )
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove qualification output directory: \(error)")
        }
    }

    @Test("independent oracle observations promote the retained corpus")
    func independentOraclePromotesCorpus() throws {
        let report = LogicQualificationReport(
            suiteID: "logic-native-fixture-v1",
            implementationID: "native-logic-engine",
            implementationVersion: "1",
            state: .corpusChecked,
            evaluations: [
                LogicQualificationCaseEvaluation(
                    caseID: "simulation-and-gate",
                    matched: true,
                    observedStatus: .completed,
                    observedDiagnosticCodes: ["LOGIC_SIMULATION_COMPLETED"],
                    observedArtifactIDs: ["logic-simulation-report", "logic-waveform"],
                    mismatches: []
                ),
                LogicQualificationCaseEvaluation(
                    caseID: "synthesis-and-gate",
                    matched: true,
                    observedStatus: .completed,
                    observedDiagnosticCodes: [
                        "LOGIC_EQUIVALENCE_REQUIRED",
                        "LOGIC_SYNTHESIS_COMPLETED"
                    ],
                    observedArtifactIDs: [
                        "logic-equivalence-request",
                        "logic-synthesis-provenance",
                        "mapped-design"
                    ],
                    mismatches: []
                ),
                LogicQualificationCaseEvaluation(
                    caseID: "simulation-signed-arithmetic",
                    matched: true,
                    observedStatus: .completed,
                    observedDiagnosticCodes: ["LOGIC_SIMULATION_COMPLETED"],
                    observedArtifactIDs: ["logic-simulation-report", "logic-waveform"],
                    mismatches: []
                ),
                LogicQualificationCaseEvaluation(
                    caseID: "simulation-vector-logical",
                    matched: true,
                    observedStatus: .completed,
                    observedDiagnosticCodes: ["LOGIC_SIMULATION_COMPLETED"],
                    observedArtifactIDs: ["logic-simulation-report", "logic-waveform"],
                    mismatches: []
                )
            ]
        )
        let oracle = try loadOracleFixture()
        let correlation = try NativeLogicQualificationOracleCorrelator().correlate(
            nativeReport: report,
            oracle: oracle
        )
        let promoted = report.includingOracleCorrelation(correlation)

        #expect(correlation.isUsableForPromotion)
        #expect(promoted.state == .oracleCorrelated)
        #expect(promoted.oraclePassed)
    }

    @Test("process qualification and human approval are separate promotion gates")
    func processAndReleasePromotionGates() throws {
        let evaluations = [
            LogicQualificationCaseEvaluation(
                caseID: "case",
                matched: true,
                observedStatus: .completed,
                observedDiagnosticCodes: ["LOGIC_SIMULATION_COMPLETED"],
                observedArtifactIDs: ["logic-report"],
                mismatches: []
            ),
        ]
        let base = LogicQualificationReport(
            suiteID: "qualification-suite",
            implementationID: "native-logic-engine",
            implementationVersion: "1",
            state: .corpusChecked,
            evaluations: evaluations
        )
        let oracle = LogicQualificationOracleObservationSet(
            oracleImplementationID: "reference-oracle",
            oracleImplementationVersion: "1",
            observations: [
                LogicQualificationOracleObservation(
                    caseID: "case",
                    observation: LogicQualificationObservation(
                        status: .completed,
                        diagnosticCodes: ["LOGIC_SIMULATION_COMPLETED"],
                        artifactIDs: ["oracle-report"]
                    )
                ),
            ]
        )
        let oracleReport = base.includingOracleCorrelation(
            try NativeLogicQualificationOracleCorrelator().correlate(
                nativeReport: base,
                oracle: oracle
            )
        )
        let process = LogicQualificationProcessEvidence(
            qualificationID: "process-qualification-1",
            suiteID: "qualification-suite",
            processID: "fixture-process",
            pdkID: "fixture-pdk",
            pdkDigest: String(repeating: "a", count: 64),
            toolImplementationID: "native-logic-engine",
            toolImplementationVersion: "1",
            environmentIdentity: "local-test-environment",
            inputArtifactIDs: ["pdk-manifest", "logic-corpus"],
            outputArtifactIDs: ["process-report"],
            inputArtifactDigests: [
                "pdk-manifest": String(repeating: "a", count: 64),
                "logic-corpus": String(repeating: "b", count: 64),
            ],
            outputArtifactDigests: [
                "process-report": String(repeating: "c", count: 64),
            ],
            metrics: ["caseCount": 1],
            qualified: true
        )
        let processReport = try oracleReport.includingProcessQualification(process)
        let approval = LogicQualificationReleaseApproval(
            approvalID: "approval-1",
            suiteID: "qualification-suite",
            qualificationID: "process-qualification-1",
            approverIdentity: "human-reviewer",
            rationale: "Reviewed process-scoped qualification evidence.",
            approved: true
        )
        let releaseReport = try processReport.includingReleaseApproval(approval)

        #expect(processReport.state == .processQualified)
        #expect(processReport.processPassed)
        #expect(releaseReport.state == .releaseEligible)
        #expect(releaseReport.isReleaseEligible)
        try releaseReport.validate()
    }

    @Test("process evidence rejects a malformed PDK digest")
    func processEvidenceRejectsMalformedPDKDigest() {
        let evidence = LogicQualificationProcessEvidence(
            qualificationID: "process-qualification-1",
            suiteID: "qualification-suite",
            processID: "fixture-process",
            pdkID: "fixture-pdk",
            pdkDigest: "pdk-digest",
            toolImplementationID: "native-logic-engine",
            toolImplementationVersion: "1",
            environmentIdentity: "local-test-environment",
            inputArtifactIDs: ["pdk-manifest"],
            outputArtifactIDs: ["process-report"],
            qualified: false
        )

        #expect(throws: LogicQualificationError.self) {
            try evidence.validate()
        }
    }

    @Test("qualified process evidence requires digest coverage for every artifact")
    func qualifiedProcessEvidenceRequiresArtifactDigestCoverage() {
        let evidence = LogicQualificationProcessEvidence(
            qualificationID: "process-qualification-1",
            suiteID: "qualification-suite",
            processID: "fixture-process",
            pdkID: "fixture-pdk",
            pdkDigest: String(repeating: "a", count: 64),
            toolImplementationID: "native-logic-engine",
            toolImplementationVersion: "1",
            environmentIdentity: "local-test-environment",
            inputArtifactIDs: ["pdk-manifest"],
            outputArtifactIDs: ["process-report"],
            qualified: true
        )

        #expect(throws: LogicQualificationError.self) {
            try evidence.validate()
        }
    }

    @Test("process and release fixtures promote the retained corpus through every gate")
    func processAndReleaseFixturesPromoteCorpus() throws {
        let suite = try loadQualificationSuiteFixture()
        let oracle = try loadOracleFixture()
        let processEvidence = try loadProcessEvidenceFixture()
        let approval = try loadReleaseApprovalFixture()
        try processEvidence.validate()
        try approval.validate()
        for (artifactID, digest) in processEvidence.inputArtifactDigests {
            let fixtureName: String
            switch artifactID {
            case "pdk-manifest": fixtureName = "pdk-manifest"
            case "logic-qualification-suite": fixtureName = "logic-qualification-suite"
            case "logic-qualification-oracle-v1": fixtureName = "logic-qualification-oracle-v1"
            default: throw LogicExecutionError.invalidArtifact("unknown process fixture input \(artifactID)")
            }
            let data = try Data(contentsOf: try LogicEngineTestFixture.url(named: fixtureName))
            #expect(try SHA256ContentDigester().digest(data: data, using: .sha256).hexadecimalValue == digest)
        }
        let processOutput = try Data(contentsOf: try LogicEngineTestFixture.url(named: "logic-qualification-process-output"))
        #expect(
            try SHA256ContentDigester().digest(data: processOutput, using: .sha256).hexadecimalValue
                == processEvidence.outputArtifactDigests["logic-qualification-process-output"]
        )

        let evaluations = suite.cases.map { qualificationCase in
            let oracleObservation = oracle.observations.first { $0.caseID == qualificationCase.caseID }
            return LogicQualificationCaseEvaluation(
                caseID: qualificationCase.caseID,
                matched: oracleObservation != nil,
                observedStatus: oracleObservation?.observation.status ?? .failed,
                observedDiagnosticCodes: oracleObservation?.observation.diagnosticCodes ?? [],
                observedArtifactIDs: oracleObservation?.observation.artifactIDs ?? [],
                mismatches: oracleObservation == nil ? ["oracle fixture case missing"] : []
            )
        }
        let base = LogicQualificationReport(
            suiteID: suite.suiteID,
            implementationID: suite.implementationID,
            implementationVersion: suite.implementationVersion,
            state: .corpusChecked,
            evaluations: evaluations
        )
        let correlated = base.includingOracleCorrelation(
            try NativeLogicQualificationOracleCorrelator().correlate(
                nativeReport: base,
                oracle: oracle
            )
        )
        let processQualified = try correlated.includingProcessQualification(processEvidence)
        let releaseEligible = try processQualified.includingReleaseApproval(approval)

        #expect(correlated.state == .oracleCorrelated)
        #expect(processQualified.state == .processQualified)
        #expect(releaseEligible.state == .releaseEligible)
        #expect(releaseEligible.isReleaseEligible)
        try releaseEligible.validate()
    }

    @Test("report validation rejects forged release state")
    func reportValidationRejectsForgedReleaseState() {
        let forged = LogicQualificationReport(
            suiteID: "qualification-suite",
            implementationID: "native-logic-engine",
            implementationVersion: "1",
            state: .releaseEligible,
            evaluations: [
                LogicQualificationCaseEvaluation(
                    caseID: "case",
                    matched: true,
                    observedStatus: .completed,
                    observedDiagnosticCodes: [],
                    observedArtifactIDs: ["report"],
                    mismatches: []
                ),
            ]
        )

        #expect(throws: LogicQualificationError.self) {
            try forged.validate()
        }
    }

    @Test("retained corpus runner records matching and mismatched cases", .timeLimit(.minutes(1)))
    func retainedCorpusRunner() async throws {
        let artifact = ArtifactReference(
            id: try ArtifactID(rawValue: "design"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "design.json"),
                role: .input,
                kind: .netlist,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: Data([0]), using: .sha256),
            byteCount: 1
        )
        let design = LogicFoundationDesignReference(
            artifact: artifact,
            topDesignName: "top",
            designRevision: artifact.digest
        )
        let passingRequest = LogicQualificationRequest.simulation(LogicSimulationRequest(
            runID: "qualification-pass",
            inputs: [artifact],
            design: design
        ))
        let blockedRequest = LogicQualificationRequest.simulation(LogicSimulationRequest(
            runID: "qualification-blocked",
            inputs: [artifact],
            design: design
        ))
        let suite = LogicQualificationSuite(
            suiteID: "logic-native-smoke-v1",
            implementationID: "native-logic-qualification",
            implementationVersion: "1",
            cases: [
                LogicQualificationCase(
                    caseID: "positive",
                    request: passingRequest,
                    expectation: LogicQualificationExpectation(expectedStatus: .completed)
                ),
                LogicQualificationCase(
                    caseID: "unsupported-boundary",
                    request: blockedRequest,
                    expectation: LogicQualificationExpectation(
                        expectedStatus: .blocked,
                        requiredDiagnosticCodes: ["LOGIC_SEMANTICS_UNSUPPORTED"]
                    )
                ),
            ]
        )
        let report = try await NativeLogicQualificationRunner(
            executor: StubQualificationExecutor()
        ).evaluate(suite)

        #expect(report.state == .corpusChecked)
        #expect(report.corpusPassed)
        #expect(report.evaluations.count == 2)
        let allMatched = report.evaluations.reduce(true) { partial, evaluation in
            partial && evaluation.matched
        }
        #expect(allMatched)
    }

    @Test("qualification suite rejects duplicate case identity")
    func duplicateCaseIdentityIsRejected() throws {
        let artifact = ArtifactReference(
            id: try ArtifactID(rawValue: "duplicate-design"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "design.json"),
                role: .input,
                kind: .netlist,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: Data([0]), using: .sha256),
            byteCount: 1
        )
        let request = LogicQualificationRequest.simulation(LogicSimulationRequest(
            runID: "duplicate-case",
            inputs: [artifact],
            design: LogicFoundationDesignReference(
                artifact: artifact,
                topDesignName: "top",
                designRevision: artifact.digest
            )
        ))
        let suite = LogicQualificationSuite(
            suiteID: "duplicate-suite",
            implementationID: "native",
            implementationVersion: "1",
            cases: [
                LogicQualificationCase(
                    caseID: "duplicate",
                    request: request,
                    expectation: LogicQualificationExpectation(expectedStatus: .completed)
                ),
                LogicQualificationCase(
                    caseID: "duplicate",
                    request: request,
                    expectation: LogicQualificationExpectation(expectedStatus: .completed)
                ),
            ]
        )

        #expect(throws: LogicQualificationError.self) {
            try suite.validate()
        }
    }
}

private func loadOracleFixture() throws -> LogicQualificationOracleObservationSet {
    guard let url = Bundle.module.url(
        forResource: "logic-qualification-oracle-v1",
        withExtension: "json",
        subdirectory: "Fixtures"
    ) else {
        throw LogicExecutionError.missingArtifact("logic-qualification-oracle-v1.json")
    }
    return try JSONDecoder().decode(
        LogicQualificationOracleObservationSet.self,
        from: Data(contentsOf: url)
    )
}

private func loadQualificationSuiteFixture() throws -> LogicQualificationSuite {
    let url = try LogicEngineTestFixture.url(named: "logic-qualification-suite")
    return try JSONDecoder().decode(LogicQualificationSuite.self, from: Data(contentsOf: url))
}

private func loadProcessEvidenceFixture() throws -> LogicQualificationProcessEvidence {
    let url = try LogicEngineTestFixture.url(named: "logic-qualification-process-evidence")
    return try JSONDecoder().decode(LogicQualificationProcessEvidence.self, from: Data(contentsOf: url))
}

private func loadReleaseApprovalFixture() throws -> LogicQualificationReleaseApproval {
    let url = try LogicEngineTestFixture.url(named: "logic-qualification-release-approval")
    return try JSONDecoder().decode(LogicQualificationReleaseApproval.self, from: Data(contentsOf: url))
}

private struct StubQualificationExecutor: LogicQualificationExecuting {
    func execute(
        _ request: LogicQualificationRequest
    ) async throws -> LogicQualificationObservation {
        switch request.runID {
        case "qualification-pass":
            return LogicQualificationObservation(
                status: .completed,
                artifactIDs: ["logic-report"]
            )
        case "qualification-blocked":
            return LogicQualificationObservation(
                status: .blocked,
                diagnosticCodes: ["LOGIC_SEMANTICS_UNSUPPORTED"],
                artifactIDs: ["blocked-report"]
            )
        default:
            throw LogicQualificationError.unsupportedRequest(request.runID)
        }
    }
}
