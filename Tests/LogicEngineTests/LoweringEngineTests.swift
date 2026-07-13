import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import Testing
import XcircuitePackage

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
        let snapshotURL = root.appending(path: "snapshot.json")
        try snapshotData.write(to: snapshotURL, options: [.atomic])
        let sourceReference = XcircuiteFileReference(
            artifactID: "rtl-snapshot",
            path: "snapshot.json",
            kind: .rtl,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: snapshotData),
            byteCount: Int64(snapshotData.count)
        )
        let request = LogicLoweringRequest(
            runID: "lowering-engine-test",
            inputs: [sourceReference],
            design: LogicDesignReference(
                artifact: sourceReference,
                topDesignName: "top",
                designDigest: snapshot.designDigest ?? ""
            ),
            artifactDirectory: "outputs"
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let result = try await NativeLogicLoweringEngine(artifactStore: store).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.executionDesign?.topDesignName == "top")
        #expect(result.payload.executionDesign?.provenance?.sourceDesignDigest == snapshot.designDigest)
        #expect(result.payload.executionDesign?.provenance?.transformationID == "native-rtl-to-execution-graph")
        #expect(result.payload.loweredNodeCount == 1)
        guard let executionDesign = result.payload.executionDesign,
              let output = result.payload.executionDesign?.artifact else {
            Issue.record("The lowering engine did not return an execution-design reference.")
            return
        }
        let outputData = try store.read(output)
        let document = try JSONDecoder().decode(LogicDesignDocument.self, from: outputData)
        #expect(document.nodes.first?.kind == .buffer)

        let repeatResult = try await NativeLogicLoweringEngine(artifactStore: store).execute(
            LogicLoweringRequest(
                runID: "lowering-engine-repeat",
                inputs: [sourceReference],
                design: request.design,
                artifactDirectory: "repeat-outputs"
            )
        )
        #expect(repeatResult.status == .completed)
        guard let repeatOutput = repeatResult.payload.executionDesign?.artifact else {
            Issue.record("The repeated lowering run did not return an execution-design reference.")
            return
        }
        #expect(try store.read(repeatOutput) == outputData)

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
        let stimulusReference = XcircuiteFileReference(
            artifactID: "stimulus",
            path: "stimulus.json",
            kind: .testPattern,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: stimulusData),
            byteCount: Int64(stimulusData.count)
        )
        let simulation = try await NativeLogicSimulationEngine(artifactStore: store).execute(
            LogicSimulationRequest(
                runID: "lowering-engine-simulation",
                inputs: [output, stimulusReference],
                design: executionDesign,
                stimulus: stimulusReference,
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
