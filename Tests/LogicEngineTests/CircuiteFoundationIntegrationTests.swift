import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import LogicSynthesis
import Testing

@Suite("LogicEngine CircuiteFoundation contract")
struct CircuiteFoundationIntegrationTests {
    @Test
    func simulationEnginePreservesArtifactIdentityAndProvenance() async throws {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "a", count: 64)
        )
        let design = ArtifactReference(
            id: try ArtifactID(rawValue: "logic-design"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/design.json"),
                role: .input,
                kind: .netlist,
                format: .json
            ),
            digest: digest,
            byteCount: 1
        )
        let output = ArtifactReference(
            id: try ArtifactID(rawValue: "logic-waveform"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "outputs/waveform.vcd"),
                role: .output,
                kind: .waveform,
                format: .vcd
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
            byteCount: 2
        )
        let fixedResult = LogicSimulationResult(
            runID: "run-1",
            status: .completed,
            payload: LogicSimulationPayload(
                traceCount: 1,
                assertionFailureCount: 0,
                waveform: output
            ),
            artifacts: [output],
            diagnostics: [],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "LogicSimulation",
                    version: "1"
                ),
                inputs: [design],
                designRevision: design.digest,
                randomSeed: 7,
                startedAt: Date(),
                completedAt: Date()
            )
        )
        let engine: any LogicSimulationExecuting = FixedSimulationEngine(result: fixedResult)
        let request = LogicSimulationRequest(
            runID: "run-1",
            design: LogicDesignArtifact(
                artifact: design,
                topDesignName: "top"
            ),
            seed: 7
        )

        let result = try await engine.execute(request)

        #expect(result.status == .completed)
        #expect(result.artifacts.map(\.id.rawValue) == ["logic-waveform"])
        #expect(result.payload.waveform?.id.rawValue == "logic-waveform")
        #expect(result.payload.assertionReport == nil)
        #expect(result.evidence.provenance.inputs == [design])
        #expect(result.evidence.provenance.randomSeed == 7)
        #expect(result.evidence.provenance.designRevision == design.digest)
        let evidenceID = result.evidence.id
        #expect(result.evidence.id == evidenceID)
        let decoded = try JSONDecoder().decode(
            LogicSimulationResult.self,
            from: JSONEncoder().encode(result)
        )
        #expect(decoded.evidence.id == evidenceID)
    }

    @Test
    func loweringEngineUsesCanonicalRevisionWhenProvidedAndDoesNotConfuseFileDigest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-logic-lowering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove lowering test root: \(error)")
            }
        }

        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(
                topModuleName: "top",
                modules: [RTLModule(
                    id: "module-top",
                    name: "top",
                    ports: [
                        RTLPort(id: "a", name: "a", direction: .input),
                        RTLPort(id: "y", name: "y", direction: .output),
                    ],
                    assignments: [RTLAssignment(
                        id: "assignment-y",
                        target: .identifier("y"),
                        value: .identifier("a")
                    )]
                )]
            )
        ))
        let snapshotData = try LogicDesignSnapshotCodec.encode(snapshot)
        try snapshotData.write(to: root.appending(path: "snapshot.json"), options: [.atomic])

        let fileDigest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: try SHA256ContentDigester()
                .digest(data: snapshotData, using: .sha256)
                .hexadecimalValue
        )
        let artifact = ArtifactReference(
            id: try ArtifactID(rawValue: "rtl-snapshot"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "snapshot.json"),
                role: .input,
                kind: .netlist,
                format: .json
            ),
            digest: fileDigest,
            byteCount: UInt64(snapshotData.count)
        )
        let request = LogicLoweringRequest(
            runID: "canonical-lowering",
            design: LogicDesignArtifact(
                artifact: artifact,
                topDesignName: "top"
            )
        )
        let engine: any LogicLoweringExecuting = NativeLogicLoweringEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        )

        let result = try await engine.execute(request)

        #expect(result.status == LogicExecutionStatus.completed)
        #expect(result.payload.sourceDesignDigest?.hexadecimalValue == snapshot.designDigest)
        #expect(result.payload.executionDesign?.topDesignName == "top")
        #expect(result.evidence.provenance.inputs == [artifact])
    }

    @Test
    func boundedEquivalenceEnginePreservesProofArtifacts() async throws {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "d", count: 64)
        )
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "reference-design"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/reference.json"),
                role: .input,
                kind: .netlist,
                format: .json
            ),
            digest: digest,
            byteCount: 1
        )
        let implementation = ArtifactReference(
            id: try ArtifactID(rawValue: "implementation-design"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/implementation.json"),
                role: .input,
                kind: .netlist,
                format: .json
            ),
            digest: digest,
            byteCount: 1
        )
        let stimulus = ArtifactReference(
            id: try ArtifactID(rawValue: "stimulus"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/stimulus.json"),
                role: .input,
                kind: .evidence,
                format: .json
            ),
            digest: digest,
            byteCount: 1
        )
        let output = ArtifactReference(
            id: try ArtifactID(rawValue: "equivalence-report"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "outputs/equivalence.json"),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "e", count: 64)
            ),
            byteCount: 4
        )
        let fixedResult = LogicBoundedTemporalEquivalenceResult(
            schemaVersion: .v1,
            runID: "run-2",
            status: .completed,
            diagnostics: [],
            artifacts: [output],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "LogicBoundedTemporalEquivalence",
                    version: "1",
                    build: "native"
                ),
                inputs: [reference, implementation, stimulus],
                invocation: ExecutionInvocation.inProcess(entryPoint: "test"),
                startedAt: Date(),
                completedAt: Date()
            ),
            payload: LogicBoundedTemporalEquivalencePayload(
                proofStatus: .proved,
                comparedSampleCount: 2,
                mismatchCount: 0,
                outputSignals: ["out"],
                equivalenceReport: output
            )
        )
        let engine: any LogicBoundedTemporalEquivalenceExecuting =
            FixedBoundedEquivalenceEngine(result: fixedResult)
        let request = LogicBoundedTemporalEquivalenceRequest(
            runID: "run-2",
            inputs: [reference, implementation, stimulus],
            referenceDesign: LogicDesignArtifact(
                artifact: reference,
                topDesignName: "top"
            ),
            implementationDesign: LogicDesignArtifact(
                artifact: implementation,
                topDesignName: "top"
            ),
            stimulus: stimulus,
            sampleLimit: 2
        )

        let result = try await engine.execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.proofStatus == .proved)
        #expect(result.payload.equivalenceReport?.id.rawValue == "equivalence-report")
        #expect(result.artifacts.map(\.id.rawValue) == ["equivalence-report"])
        #expect(result.evidence.provenance.inputs == [reference, implementation, stimulus])
    }
}

private struct FixedSimulationEngine: LogicSimulationExecuting {
    let result: LogicSimulationResult

    func execute(
        _ request: LogicSimulationRequest
    ) async throws -> LogicSimulationResult {
        result
    }
}

private struct FixedBoundedEquivalenceEngine: LogicBoundedTemporalEquivalenceExecuting {
    let result: LogicBoundedTemporalEquivalenceResult

    func execute(
        _ request: LogicBoundedTemporalEquivalenceRequest
    ) async throws -> LogicBoundedTemporalEquivalenceResult {
        result
    }
}
