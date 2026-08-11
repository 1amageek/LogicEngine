import Foundation
import LogicEngineCore
import LogicIR
import LogicSynthesis
import PDKCore
import Testing
import TimingCore
import CircuiteFoundation
import CircuiteFoundationCrypto

@Suite("Native logic synthesis")
struct SynthesisTests {
    @Test("lowers, maps, emits provenance, and keeps equivalence as a required gate")
    func synthesisProducesMappedDesign() async throws {
        let outputDirectory = try LogicEngineTestFixture.temporaryOutputDirectory()
        let request = try LogicEngineTestFixture.synthesisRequest(outputDirectory: outputDirectory)
        let store = FileSystemLogicArtifactStore(rootDirectory: URL(fileURLWithPath: "/"))
        let result = try await NativeLogicSynthesisEngine(artifactStore: store).execute(request)

        #expect(
            result.status == .completed,
            "Diagnostics: \(result.diagnostics)"
        )
        #expect(result.payload.mappedCellCount == 1)
        #expect(result.payload.loweredNodeCount == 1)
        #expect(result.payload.optimizedNodeCount == 1)
        #expect(result.payload.totalArea == 1)
        #expect(result.payload.equivalenceRequired)
        #expect(result.payload.acceptanceState == .pendingEquivalence)
        #expect(result.payload.equivalenceRequest != nil)
        #expect(result.diagnostics.contains { $0.code.rawValue == "LOGIC_EQUIVALENCE_REQUIRED" })
        guard let mappedDesign = result.payload.mappedDesign else {
            Issue.record("mapped design is missing")
            return
        }
        #expect(mappedDesign.designDigest == mappedDesign.artifact.digest.hexadecimalValue)
        let mappedBinding = try LogicArtifactBinding.require(
            mappedDesign.artifact,
            in: result.artifactBindings
        )
        let mappedData = try store.read(mappedBinding)
        let document = try JSONDecoder().decode(LogicDesignDocument.self, from: mappedData)
        #expect(document.nodes.first?.parameters["mappedCell"] == "AND2_X1")
        #expect(result.payload.provenance != nil)
        guard let equivalenceRequest = result.payload.equivalenceRequest else {
            Issue.record("equivalence request artifact is missing")
            return
        }
        let equivalenceBinding = try LogicArtifactBinding.require(
            equivalenceRequest,
            in: result.artifactBindings
        )
        let equivalenceData = try store.read(equivalenceBinding)
        let equivalenceRequestPayload = try JSONDecoder().decode(LogicSynthesisEquivalenceRequest.self, from: equivalenceData)
        try equivalenceRequestPayload.validate()
        #expect(
            equivalenceRequestPayload.mappedDesign.designDigest
                == mappedDesign.artifact.digest.hexadecimalValue
        )
    }

    @Test("library membership controls mapping without caller-issued qualification")
    func mappingIgnoresCallerQualificationFlags() async throws {
        let outputDirectory = try LogicEngineTestFixture.temporaryOutputDirectory()
        let designBinding = try LogicEngineTestFixture.binding(named: "and-design", kind: .netlist)
        let design = LogicDesignReference(
            artifact: designBinding.reference,
            topDesignName: "and_top",
            canonicalDesignDigest: designBinding.digest
        )
        let library = try LogicEngineTestFixture.binding(named: "logic-cells-unqualified", kind: .timingLibrary, format: .json)
        let constraints = try LogicEngineTestFixture.binding(named: "logic-constraints", kind: .constraint, format: .json)
        let pdk = try LogicEngineTestFixture.binding(named: "pdk-manifest", kind: .technology, format: .json)
        let request = LogicSynthesisRequest(
            runID: "logic-synthesis-no-cell",
            inputBindings: [designBinding],
            design: design,
            libraries: [TimingLibraryReference(
                artifact: try TimingArtifactBinding(
                    reference: library.reference,
                    availability: LogicEngineTestFixture.timingAvailability(
                        from: library.availability
                    )
                ),
                cornerIDs: ["typical"]
            )],
            constraints: constraints,
            pdk: PDKReference(
                manifest: pdk.reference,
                manifestLocator: try LogicEngineTestFixture.locator(
                    named: "pdk-manifest",
                    kind: .technology,
                    format: .json
                ),
                processID: "logic-fixture",
                version: "1",
                digest: pdk.digest.hexadecimalValue
            ),
            artifactDirectory: outputDirectory.path(percentEncoded: false)
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: URL(fileURLWithPath: "/"))
        let result = try await NativeLogicSynthesisEngine(artifactStore: store).execute(request)
        #expect(
            result.status == .completed,
            "Diagnostics: \(result.diagnostics)"
        )
        #expect(result.payload.mappedCellCount == 1)
    }

    @Test("accepts only matching proved equivalence evidence")
    func acceptsMatchingEquivalenceEvidence() throws {
        let sourceArtifact = try artifact(id: "source", path: "source.json", kind: .netlist)
        let mappedArtifact = try artifact(id: "mapped", path: "mapped.json", kind: .netlist)
        let proof = try artifact(id: "proof", path: "proof.json", kind: .report)
        let provenance = try artifact(id: "provenance", path: "provenance.json", kind: .report)
        let pdk = try artifact(id: "pdk", path: "pdk.json", kind: .technology)
        let sourceDesign = LogicDesignReference(
            artifact: sourceArtifact,
            topDesignName: "top",
            designDigest: sourceArtifact.digest.hexadecimalValue
        )
        let mappedDesign = LogicDesignReference(
            artifact: mappedArtifact,
            topDesignName: "top",
            designDigest: mappedArtifact.digest.hexadecimalValue
        )
        let request = LogicSynthesisEquivalenceRequest(
            runID: "acceptance-run",
            topDesignName: "top",
            sourceDesign: sourceDesign,
            mappedDesign: mappedDesign,
            synthesisProvenance: provenance,
            pdkArtifact: pdk
        )
        let executionProvenance = try ExecutionProvenance(
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "logic-equivalence",
                version: "1.0.0"
            ),
            inputs: [sourceArtifact, mappedArtifact, provenance, pdk],
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 1)
        )
        let evidence = LogicSynthesisEquivalenceEvidence(
            runID: request.runID,
            sourceDesignDigest: sourceDesign.designDigest,
            mappedDesignDigest: mappedDesign.designDigest,
            proofScope: request.proofScope,
            status: .proved,
            proofArtifact: proof,
            provenance: executionProvenance
        )
        let result = NativeLogicSynthesisAcceptanceEvaluator().evaluate(request: request, evidence: evidence)

        #expect(result.state == .accepted)
        #expect(result.diagnostics.first?.code.rawValue == "LOGIC_SYNTHESIS_ACCEPTED")

        let mismatchedEvidence = LogicSynthesisEquivalenceEvidence(
            runID: request.runID,
            sourceDesignDigest: sourceDesign.designDigest,
            mappedDesignDigest: "other-mapped-digest",
            proofScope: request.proofScope,
            status: .proved,
            proofArtifact: proof,
            provenance: executionProvenance
        )
        let rejected = NativeLogicSynthesisAcceptanceEvaluator().evaluate(
            request: request,
            evidence: mismatchedEvidence
        )
        #expect(rejected.state == .rejected)
        #expect(rejected.diagnostics.first?.code.rawValue == "LOGIC_EQUIVALENCE_MAPPED_DIGEST_MISMATCH")
    }

    private func artifact(
        id: String,
        path: String,
        kind: ArtifactKind
    ) throws -> ArtifactReference {
        let data = Data([0])
        return try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count),
            descriptor: ArtifactDescriptor(role: .input, kind: kind, format: .json)
        )
    }
}
