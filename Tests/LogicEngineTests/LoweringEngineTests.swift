import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation

@Suite("Logic lowering engine")
struct LoweringEngineTests {
    @Test("reads a snapshot reference and persists an execution-design reference")
    func persistsExecutionDesignArtifact() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
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
        let canonicalDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        let snapshotURL = root.appending(path: "snapshot.json")
        try snapshotData.write(to: snapshotURL, options: [.atomic])
        let sourceReference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: snapshotData, using: .sha256),
            byteCount: UInt64(snapshotData.count),
            descriptor: ArtifactDescriptor(role: .input, kind: .rtl, format: .json)
        )
        let sourceBinding = try LogicArtifactBinding.local(
            reference: sourceReference,
            fileURL: snapshotURL
        )
        let request = LogicLoweringRequest(
            runID: "lowering-engine-test",
            inputBindings: [sourceBinding],
            design: LogicDesignReference(
                artifact: sourceBinding.reference,
                topDesignName: "top",
                canonicalDesignDigest: try ContentDigest(algorithm: .sha256, hexadecimalValue: canonicalDigest)
            ),
            artifactDirectory: "outputs"
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let result = try await NativeLogicLoweringEngine(artifactStore: store).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.executionDesign?.topDesignName == "top")
        #expect(result.payload.executionDesign?.designDigest.isEmpty == false)
        #expect(result.payload.loweredNodeCount == 1)
        guard let executionDesign = result.payload.executionDesign,
              let output = result.payload.executionDesign?.artifact else {
            Issue.record("The lowering engine did not return an execution-design reference.")
            return
        }
        let outputBinding = try LogicArtifactBinding.require(output, in: result.artifactBindings)
        let outputData = try store.read(outputBinding)
        let document = try JSONDecoder().decode(LogicDesignDocument.self, from: outputData)
        #expect(document.nodes.first?.kind == .buffer)

        let repeatResult = try await NativeLogicLoweringEngine(artifactStore: store).execute(
            LogicLoweringRequest(
                runID: "lowering-engine-repeat",
                inputBindings: [sourceBinding],
                design: request.design,
                artifactDirectory: "repeat-outputs"
            )
        )
        #expect(repeatResult.status == .completed)
        guard let repeatOutput = repeatResult.payload.executionDesign?.artifact else {
            Issue.record("The repeated lowering run did not return an execution-design reference.")
            return
        }
        let repeatOutputBinding = try LogicArtifactBinding.require(
            repeatOutput,
            in: repeatResult.artifactBindings
        )
        #expect(try store.read(repeatOutputBinding) == outputData)

        let stimulus = LogicStimulusDocument(
            events: [LogicStimulusEvent(
                time: 0,
                assignments: ["a": try LogicVector(string: "1")]
            )],
            assertions: [LogicAssertion(
                id: "y-is-high",
                time: 0,
                signal: "y",
                expected: try LogicVector(string: "1")
            )]
        )
        let stimulusData = try JSONEncoder().encode(stimulus)
        try stimulusData.write(to: root.appending(path: "stimulus.json"), options: [.atomic])
        let stimulusReference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: stimulusData, using: .sha256),
            byteCount: UInt64(stimulusData.count),
            descriptor: ArtifactDescriptor(role: .input, kind: .testPattern, format: .json)
        )
        let stimulusBinding = try LogicArtifactBinding.local(
            reference: stimulusReference,
            fileURL: root.appending(path: "stimulus.json")
        )
        let simulation = try await NativeLogicSimulationEngine(artifactStore: store).execute(
            LogicSimulationRequest(
                runID: "lowering-engine-simulation",
                inputBindings: [outputBinding, stimulusBinding],
                design: executionDesign,
                stimulus: stimulusBinding,
                artifactDirectory: "simulation-output"
            )
        )
        #expect(simulation.status == .completed)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "logic-lowering-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
