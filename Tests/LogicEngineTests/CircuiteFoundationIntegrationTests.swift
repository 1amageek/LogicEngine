import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import LogicSynthesis
import Testing
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation

@Suite("LogicEngine CircuiteFoundation contract")
struct CircuiteFoundationIntegrationTests {
    @Test
    func simulationEnginePreservesArtifactIdentityAndProvenance() async throws {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "a", count: 64)
        )
        let design = try binding(
            path: "inputs/design.json",
            role: .input,
            kind: .netlist,
            format: .json,
            digest: digest,
            byteCount: 1
        )
        let output = try binding(
            path: "outputs/waveform.vcd",
            role: .output,
            kind: .waveform,
            format: .vcd,
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
            byteCount: 2
        )
        let fixedResult = try LogicSimulationResult(
            runID: "run-1",
            status: .completed,
            payload: LogicSimulationPayload(
                traceCount: 1,
                assertionFailureCount: 0,
                waveform: output.reference
            ),
            artifactBindings: [output],
            diagnostics: [],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "LogicSimulation",
                    version: "1"
                ),
                inputs: [design.reference],
                randomSeed: 7,
                startedAt: Date(),
                completedAt: Date()
            )
        )
        let engine: any LogicSimulationExecuting = FixedSimulationEngine(result: fixedResult)
        let request = LogicSimulationRequest(
            runID: "run-1",
            inputBindings: [design],
            design: LogicDesignReference(
                artifact: design.reference,
                topDesignName: "top",
                canonicalDesignDigest: design.digest
            ),
            seed: 7
        )

        let result = try await engine.execute(request)

        #expect(result.status == .completed)
        #expect(result.artifacts == [output.reference])
        #expect(result.payload.waveform == output.reference)
        #expect(result.payload.assertionReport == nil)
        #expect(result.evidence.provenance.inputs == [design.reference])
        #expect(result.evidence.provenance.randomSeed == 7)
        #expect(result.evidence.provenance.inputDesignRevision == nil)
        #expect(result.evidence.provenance.outputDesignRevision == nil)
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
        guard let snapshotDigest = snapshot.designDigest else {
            Issue.record("Finalized logic design snapshot is missing its canonical digest")
            return
        }
        let snapshotData = try LogicDesignSnapshotCodec.encode(snapshot)
        try snapshotData.write(to: root.appending(path: "snapshot.json"), options: [.atomic])

        let fileDigest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: try SHA256ContentDigester()
                .digest(data: snapshotData, using: .sha256)
                .hexadecimalValue
        )
        let artifact = try binding(
            path: "snapshot.json",
            role: .input,
            kind: .netlist,
            format: .json,
            digest: fileDigest,
            byteCount: UInt64(snapshotData.count)
        )
        let request = LogicLoweringRequest(
            runID: "canonical-lowering",
            inputBindings: [artifact],
            design: LogicDesignReference(
                artifact: artifact.reference,
                topDesignName: "top",
                canonicalDesignDigest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: snapshotDigest
                )
            )
        )
        let engine: any LogicLoweringExecuting = NativeLogicLoweringEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        )

        let result = try await engine.execute(request)

        #expect(result.status == LogicExecutionStatus.completed)
        #expect(result.payload.sourceDesignDigest?.hexadecimalValue == snapshotDigest)
        #expect(result.payload.executionDesign?.topDesignName == "top")
        #expect(result.evidence.provenance.inputs == [artifact.reference])
    }

    @Test
    func boundedEquivalenceEnginePreservesProofArtifacts() async throws {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "d", count: 64)
        )
        let reference = try binding(
            path: "inputs/reference.json",
            role: .input,
            kind: .netlist,
            format: .json,
            digest: digest,
            byteCount: 1
        )
        let implementation = try binding(
            path: "inputs/implementation.json",
            role: .input,
            kind: .netlist,
            format: .json,
            digest: digest,
            byteCount: 1
        )
        let stimulus = try binding(
            path: "inputs/stimulus.json",
            role: .input,
            kind: .evidence,
            format: .json,
            digest: digest,
            byteCount: 1
        )
        let output = try binding(
            path: "outputs/equivalence.json",
            role: .output,
            kind: .report,
            format: .json,
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "e", count: 64)
            ),
            byteCount: 4
        )
        let fixedResult = try LogicBoundedTemporalEquivalenceResult(
            schemaVersion: .v2,
            runID: "run-2",
            status: .completed,
            diagnostics: [],
            artifactBindings: [output],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "LogicBoundedTemporalEquivalence",
                    version: "1",
                    build: "native"
                ),
                inputs: [reference.reference, implementation.reference, stimulus.reference],
                invocation: ExecutionInvocation.inProcess(entryPoint: "test"),
                startedAt: Date(),
                completedAt: Date()
            ),
            payload: LogicBoundedTemporalEquivalencePayload(
                proofStatus: .proved,
                comparedSampleCount: 2,
                mismatchCount: 0,
                outputSignals: ["out"],
                equivalenceReport: output.reference
            )
        )
        let engine: any LogicBoundedTemporalEquivalenceExecuting =
            FixedBoundedEquivalenceEngine(result: fixedResult)
        let request = LogicBoundedTemporalEquivalenceRequest(
            runID: "run-2",
            inputBindings: [reference, implementation, stimulus],
            referenceDesign: LogicDesignReference(
                artifact: reference.reference,
                topDesignName: "top",
                canonicalDesignDigest: reference.digest
            ),
            implementationDesign: LogicDesignReference(
                artifact: implementation.reference,
                topDesignName: "top",
                canonicalDesignDigest: implementation.digest
            ),
            stimulus: stimulus,
            sampleLimit: 2
        )

        let result = try await engine.execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.proofStatus == .proved)
        #expect(result.payload.equivalenceReport == output.reference)
        #expect(result.artifacts == [output.reference])
        #expect(result.evidence.provenance.inputs == [
            reference.reference,
            implementation.reference,
            stimulus.reference,
        ])
    }

    private func binding(
        path: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat,
        digest: ContentDigest,
        byteCount: UInt64
    ) throws -> LogicArtifactBinding {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        )
        let reference = try ArtifactReference(
            digest: digest,
            byteCount: byteCount,
            descriptor: locator.descriptor
        )
        return try LogicArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(
                    rawValue: LogicArtifactBinding.workspaceRootIdentifier
                ),
                relativePath: try ArtifactRelativePath(
                    segments: path.split(separator: "/").map(String.init)
                )
            ),
        )
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
