import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import LogicSynthesis
import Testing
import XcircuitePackage

@Suite("LogicEngine CircuiteFoundation boundary")
struct CircuiteFoundationIntegrationTests {
    @Test
    func simulationFoundationEnginePreservesArtifactIdentityAndProvenance() async throws {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "a", count: 64)
        )
        let design = ArtifactReference(
            id: try ArtifactID(rawValue: "logic-design"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/design.json"),
                kind: .netlist,
                format: .json
            ),
            digest: digest,
            byteCount: 1
        )
        let output = XcircuiteFileReference(
            artifactID: "logic-waveform",
            path: "outputs/waveform.vcd",
            kind: .waveform,
            format: .vcd,
            sha256: String(repeating: "b", count: 64),
            byteCount: 2
        )
        let startedAt = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 101)
        let legacyResult = XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: "run-1",
            status: .completed,
            artifacts: [output],
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "LogicSimulation",
                implementationID: "native",
                implementationVersion: "1",
                startedAt: startedAt,
                completedAt: completedAt,
                seed: 7
            ),
            payload: LogicSimulationPayload(
                traceCount: 1,
                assertionFailureCount: 0,
                waveform: output
            )
        )
        let engine = NativeLogicSimulationFoundationEngine(
            legacyEngine: FixedSimulationEngine(result: legacyResult)
        )
        let request = LogicSimulationFoundationRequest(
            runID: "run-1",
            design: LogicFoundationDesignReference(
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
        #expect(result.evidence.provenance.startedAt == startedAt)
        #expect(result.evidence.provenance.completedAt == completedAt)
    }

    @Test
    func loweringFoundationEngineUsesCanonicalRevisionWhenProvidedAndDoesNotConfuseFileDigest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-foundation-lowering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove lowering Foundation test root: \(error)")
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
            hexadecimalValue: XcircuiteHasher().sha256(data: snapshotData)
        )
        let artifact = ArtifactReference(
            id: try ArtifactID(rawValue: "rtl-snapshot"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "snapshot.json"),
                kind: .netlist,
                format: .json
            ),
            digest: fileDigest,
            byteCount: UInt64(snapshotData.count)
        )
        let request = LogicLoweringFoundationRequest(
            runID: "foundation-lowering",
            design: LogicFoundationDesignReference(
                artifact: artifact,
                topDesignName: "top"
            )
        )
        let legacyEngine = NativeLogicLoweringEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        )
        let engine = NativeLogicLoweringFoundationEngine(legacyEngine: legacyEngine)

        let result = try await engine.execute(request)

        #expect(result.status == LogicExecutionStatus.completed)
        #expect(result.payload.sourceDesignDigest?.hexadecimalValue == snapshot.designDigest)
        #expect(result.payload.executionDesign?.topDesignName == "top")
        #expect(result.evidence.provenance.inputs == [artifact])
    }

    @Test
    func bridgeDerivesStableIdentityForLegacyReferenceWithoutID() throws {
        let legacy = XcircuiteFileReference(
            path: "outputs/report.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "c", count: 64),
            byteCount: 3
        )
        let bridge = LogicFoundationArtifactBridge()

        let first = try bridge.foundationReference(from: legacy)
        let second = try bridge.foundationReference(from: legacy)

        #expect(first.id == second.id)
        #expect(first.id.rawValue.hasPrefix("derived-"))
        #expect(first.locator.kind == .report)
        #expect(first.locator.format == .json)
    }

    @Test
    func boundedEquivalenceFoundationEnginePreservesProofArtifacts() async throws {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "d", count: 64)
        )
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "reference-design"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/reference.json"),
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
                kind: .evidence,
                format: .json
            ),
            digest: digest,
            byteCount: 1
        )
        let output = XcircuiteFileReference(
            artifactID: "equivalence-report",
            path: "outputs/equivalence.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "e", count: 64),
            byteCount: 4
        )
        let timestamp = Date(timeIntervalSince1970: 200)
        let legacyResult = XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: "run-2",
            status: .completed,
            artifacts: [output],
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "LogicBoundedTemporalEquivalence",
                implementationID: "native",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1)
            ),
            payload: LogicBoundedTemporalEquivalencePayload(
                proofStatus: .proved,
                comparedSampleCount: 2,
                mismatchCount: 0,
                outputSignals: ["out"],
                equivalenceReport: output
            )
        )
        let engine = NativeLogicBoundedTemporalEquivalenceFoundationEngine(
            legacyEngine: FixedBoundedEquivalenceEngine(result: legacyResult)
        )
        let request = LogicBoundedTemporalEquivalenceFoundationRequest(
            runID: "run-2",
            referenceDesign: LogicFoundationDesignReference(
                artifact: reference,
                topDesignName: "top"
            ),
            implementationDesign: LogicFoundationDesignReference(
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
    let result: XcircuiteEngineResultEnvelope<LogicSimulationPayload>

    func execute(
        _ request: LogicSimulationRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicSimulationPayload> {
        result
    }
}

private struct FixedBoundedEquivalenceEngine: LogicBoundedTemporalEquivalenceExecuting {
    let result: XcircuiteEngineResultEnvelope<LogicBoundedTemporalEquivalencePayload>

    func execute(
        _ request: LogicBoundedTemporalEquivalenceRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicBoundedTemporalEquivalencePayload> {
        result
    }
}
