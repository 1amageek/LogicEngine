import Foundation
import LogicEngineCore
import LogicIR
import LogicSynthesis
import PDKCore
import Testing
import TimingCore
import XcircuitePackage

@Suite("Native logic synthesis")
struct SynthesisTests {
    @Test("lowers, maps, emits provenance, and keeps equivalence as a required gate")
    func synthesisProducesMappedDesign() async throws {
        let outputDirectory = try LogicEngineTestFixture.temporaryOutputDirectory()
        let request = try LogicEngineTestFixture.synthesisRequest(outputDirectory: outputDirectory)
        let store = FileSystemLogicArtifactStore(rootDirectory: URL(fileURLWithPath: "/"))
        let envelope = try await NativeLogicSynthesisEngine(artifactStore: store).execute(request)

        #expect(envelope.status == .completed)
        #expect(envelope.payload.mappedCellCount == 1)
        #expect(envelope.payload.loweredNodeCount == 1)
        #expect(envelope.payload.optimizedNodeCount == 1)
        #expect(envelope.payload.totalArea == 1)
        #expect(envelope.payload.equivalenceRequired)
        #expect(envelope.payload.acceptanceState == .pendingEquivalence)
        #expect(envelope.payload.equivalenceRequest != nil)
        #expect(envelope.diagnostics.contains { $0.code == "LOGIC_EQUIVALENCE_REQUIRED" })
        guard let mappedDesign = envelope.payload.mappedDesign else {
            Issue.record("mapped design is missing")
            return
        }
        #expect(mappedDesign.provenance?.sourceDesignDigest == request.design.designDigest)
        #expect(mappedDesign.provenance?.inputDesignDigest == request.design.designDigest)
        #expect(mappedDesign.provenance?.transformationID == "native-synthesis")
        let mappedData = try Data(contentsOf: URL(fileURLWithPath: mappedDesign.artifact.path))
        let document = try JSONDecoder().decode(LogicDesignDocument.self, from: mappedData)
        #expect(document.nodes.first?.parameters["mappedCell"] == "AND2_X1")
        #expect(envelope.payload.provenance != nil)
        guard let equivalenceRequest = envelope.payload.equivalenceRequest else {
            Issue.record("equivalence request artifact is missing")
            return
        }
        let equivalenceData = try Data(contentsOf: URL(fileURLWithPath: equivalenceRequest.path))
        let equivalenceRequestPayload = try JSONDecoder().decode(LogicSynthesisEquivalenceRequest.self, from: equivalenceData)
        try equivalenceRequestPayload.validate()
        #expect(equivalenceRequestPayload.mappedDesign == mappedDesign)
    }

    @Test("missing qualified cells block mapping instead of passing")
    func missingQualifiedCellBlocks() async throws {
        let outputDirectory = try LogicEngineTestFixture.temporaryOutputDirectory()
        let design = try LogicEngineTestFixture.designReference()
        let library = try LogicEngineTestFixture.reference(named: "logic-cells-unqualified", kind: .timingLibrary, format: .json)
        let constraints = try LogicEngineTestFixture.reference(named: "logic-constraints", kind: .constraint, format: .json)
        let pdk = try LogicEngineTestFixture.reference(named: "pdk-manifest", kind: .technology, format: .json)
        guard let pdkDigest = pdk.sha256 else {
            throw LogicExecutionError.artifactDigestMismatch(pdk.path)
        }
        let request = LogicSynthesisRequest(
            runID: "logic-synthesis-no-cell",
            inputs: [design.artifact, constraints, pdk],
            design: design,
            libraries: [TimingLibraryReference(artifact: library, cornerIDs: ["typical"])],
            constraints: TimingConstraintReference(artifact: constraints, modeIDs: ["default"]),
            pdk: PDKReference(manifest: pdk, processID: "logic-fixture", version: "1", digest: pdkDigest),
            artifactDirectory: outputDirectory.path(percentEncoded: false)
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: URL(fileURLWithPath: "/"))
        let envelope = try await NativeLogicSynthesisEngine(artifactStore: store).execute(request)
        #expect(envelope.status == .blocked)
        #expect(envelope.diagnostics.first?.code == "LOGIC_CELL_UNQUALIFIED")
    }

    @Test("accepts only matching proved equivalence evidence")
    func acceptsMatchingEquivalenceEvidence() throws {
        let sourceDesign = LogicDesignReference(
            artifact: XcircuiteFileReference(
                artifactID: "source",
                path: "source.json",
                kind: .netlist,
                format: .json,
                sha256: "source-digest",
                byteCount: 1
            ),
            topDesignName: "top",
            designDigest: "source-digest"
        )
        let mappedDesign = LogicDesignReference(
            artifact: XcircuiteFileReference(
                artifactID: "mapped",
                path: "mapped.json",
                kind: .netlist,
                format: .json,
                sha256: "mapped-digest",
                byteCount: 1
            ),
            topDesignName: "top",
            designDigest: "mapped-digest"
        )
        let proof = XcircuiteFileReference(
            artifactID: "proof",
            path: "proof.json",
            kind: .report,
            format: .json,
            sha256: "proof-digest",
            byteCount: 1
        )
        let provenance = XcircuiteFileReference(
            artifactID: "provenance",
            path: "provenance.json",
            kind: .report,
            format: .json,
            sha256: "provenance-digest",
            byteCount: 1
        )
        let request = LogicSynthesisEquivalenceRequest(
            runID: "acceptance-run",
            topDesignName: "top",
            sourceDesign: sourceDesign,
            mappedDesign: mappedDesign,
            synthesisProvenance: provenance
        )
        let evidence = LogicSynthesisEquivalenceEvidence(
            runID: request.runID,
            sourceDesignDigest: sourceDesign.designDigest,
            mappedDesignDigest: mappedDesign.designDigest,
            proofScope: request.proofScope,
            status: .proved,
            proofArtifact: proof
        )
        let result = NativeLogicSynthesisAcceptanceEvaluator().evaluate(request: request, evidence: evidence)

        #expect(result.state == .accepted)
        #expect(result.diagnostics.first?.code == "LOGIC_SYNTHESIS_ACCEPTED")

        let mismatchedEvidence = LogicSynthesisEquivalenceEvidence(
            runID: request.runID,
            sourceDesignDigest: sourceDesign.designDigest,
            mappedDesignDigest: "other-mapped-digest",
            proofScope: request.proofScope,
            status: .proved,
            proofArtifact: proof
        )
        let rejected = NativeLogicSynthesisAcceptanceEvaluator().evaluate(
            request: request,
            evidence: mismatchedEvidence
        )
        #expect(rejected.state == .rejected)
        #expect(rejected.diagnostics.first?.code == "LOGIC_EQUIVALENCE_MAPPED_DIGEST_MISMATCH")
    }
}
