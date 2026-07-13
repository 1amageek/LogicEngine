import Foundation
import LogicEngineCore
import LogicIR
import LogicSynthesis
import Testing
import XcircuitePackage

@Suite("Bounded temporal equivalence")
struct TemporalEquivalenceTests {
    @Test("proves matching execution traces within the declared bound")
    func provesMatchingTraces() async throws {
        let root = try makeRoot(name: "bounded-temporal-proof")
        defer { removeRoot(root) }

        let reference = makeBufferDesign(name: "temporal_top")
        let implementation = makeBufferDesign(name: "temporal_top")
        let stimulus = LogicStimulusDocument(events: [
            LogicStimulusEvent(time: 0, assignments: ["a": LogicVector(.zero)]),
            LogicStimulusEvent(time: 1, assignments: ["a": LogicVector(.one)]),
        ])
        let referenceArtifact = try writeJSON(reference, name: "reference.json", root: root, kind: .netlist)
        let implementationArtifact = try writeJSON(implementation, name: "implementation.json", root: root, kind: .netlist)
        let stimulusArtifact = try writeJSON(stimulus, name: "stimulus.json", root: root, kind: .testPattern)
        let request = makeRequest(
            runID: "bounded-temporal-proof",
            referenceArtifact: referenceArtifact,
            implementationArtifact: implementationArtifact,
            stimulusArtifact: stimulusArtifact,
            sampleLimit: 4
        )

        let result = try await NativeLogicBoundedTemporalEquivalenceEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.proofStatus == .proved)
        #expect(result.payload.mismatchCount == 0)
        #expect(result.payload.comparedSampleCount == 2)
        #expect(result.payload.counterexample == nil)
        #expect(result.artifacts.contains { $0.artifactID == "logic-bounded-temporal-equivalence-report" })
        let reportReference = try #require(result.payload.equivalenceReport)
        let reportData = try Data(contentsOf: root.appending(path: reportReference.path))
        let report = try JSONDecoder().decode(LogicBoundedTemporalEquivalenceReport.self, from: reportData)
        try report.validate()
        #expect(!report.requestDigest.isEmpty)
        #expect(report.stimulusDigest == stimulusArtifact.sha256)
    }

    @Test("persists a counterexample for a bounded temporal mismatch")
    func persistsCounterexample() async throws {
        let root = try makeRoot(name: "bounded-temporal-counterexample")
        defer { removeRoot(root) }

        let reference = makeBufferDesign(name: "temporal_top")
        let implementation = makeConstantDesign(name: "temporal_top", value: "0")
        let stimulus = LogicStimulusDocument(events: [
            LogicStimulusEvent(time: 0, assignments: ["a": LogicVector(.zero)]),
            LogicStimulusEvent(time: 1, assignments: ["a": LogicVector(.one)]),
        ])
        let referenceArtifact = try writeJSON(reference, name: "reference.json", root: root, kind: .netlist)
        let implementationArtifact = try writeJSON(implementation, name: "implementation.json", root: root, kind: .netlist)
        let stimulusArtifact = try writeJSON(stimulus, name: "stimulus.json", root: root, kind: .testPattern)
        let request = makeRequest(
            runID: "bounded-temporal-counterexample",
            referenceArtifact: referenceArtifact,
            implementationArtifact: implementationArtifact,
            stimulusArtifact: stimulusArtifact,
            sampleLimit: 4
        )

        let result = try await NativeLogicBoundedTemporalEquivalenceEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .failed)
        #expect(result.payload.proofStatus == .counterexample)
        #expect(result.payload.mismatchCount == 1)
        #expect(result.payload.counterexample != nil)
        #expect(result.diagnostics.contains { $0.code == "LOGIC_BOUNDED_TEMPORAL_COUNTEREXAMPLE" })
    }

    @Test("blocks a trace that exceeds the declared sample bound")
    func blocksTraceBeyondBound() async throws {
        let root = try makeRoot(name: "bounded-temporal-bound")
        defer { removeRoot(root) }

        let design = makeBufferDesign(name: "temporal_top")
        let stimulus = LogicStimulusDocument(events: [
            LogicStimulusEvent(time: 0, assignments: ["a": LogicVector(.zero)]),
            LogicStimulusEvent(time: 1, assignments: ["a": LogicVector(.one)]),
        ])
        let designArtifact = try writeJSON(design, name: "design.json", root: root, kind: .netlist)
        let stimulusArtifact = try writeJSON(stimulus, name: "stimulus.json", root: root, kind: .testPattern)
        let request = makeRequest(
            runID: "bounded-temporal-bound",
            referenceArtifact: designArtifact,
            implementationArtifact: designArtifact,
            stimulusArtifact: stimulusArtifact,
            sampleLimit: 1
        )

        let result = try await NativeLogicBoundedTemporalEquivalenceEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.proofStatus == .blocked)
        #expect(result.diagnostics.contains { $0.code == "LOGIC_PREREQUISITE_MISSING" })
    }

    private func makeRequest(
        runID: String,
        referenceArtifact: XcircuiteFileReference,
        implementationArtifact: XcircuiteFileReference,
        stimulusArtifact: XcircuiteFileReference,
        sampleLimit: Int
    ) -> LogicBoundedTemporalEquivalenceRequest {
        LogicBoundedTemporalEquivalenceRequest(
            runID: runID,
            inputs: [referenceArtifact, implementationArtifact, stimulusArtifact],
            referenceDesign: LogicDesignReference(
                artifact: referenceArtifact,
                topDesignName: "temporal_top",
                designDigest: referenceArtifact.sha256 ?? ""
            ),
            implementationDesign: LogicDesignReference(
                artifact: implementationArtifact,
                topDesignName: "temporal_top",
                designDigest: implementationArtifact.sha256 ?? ""
            ),
            stimulus: stimulusArtifact,
            outputSignals: ["y"],
            sampleLimit: sampleLimit,
            artifactDirectory: "outputs"
        )
    }

    private func makeBufferDesign(name: String) -> LogicDesignDocument {
        LogicDesignDocument(
            topDesignName: name,
            ports: [
                LogicPort(name: "a", direction: .input),
                LogicPort(name: "y", direction: .output),
            ],
            signals: [
                LogicSignal(name: "a"),
                LogicSignal(name: "y"),
            ],
            nodes: [LogicNode(id: "buffer", kind: .buffer, inputs: ["a"], outputs: ["y"])]
        )
    }

    private func makeConstantDesign(name: String, value: String) -> LogicDesignDocument {
        LogicDesignDocument(
            topDesignName: name,
            ports: [
                LogicPort(name: "a", direction: .input),
                LogicPort(name: "y", direction: .output),
            ],
            signals: [
                LogicSignal(name: "a"),
                LogicSignal(name: "y"),
            ],
            nodes: [LogicNode(
                id: "constant",
                kind: .constant,
                inputs: [],
                outputs: ["y"],
                parameters: ["value": value]
            )]
        )
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-engine-" + name + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove bounded temporal equivalence root: \(error)")
        }
    }

    private func writeJSON<T: Encodable>(
        _ value: T,
        name: String,
        root: URL,
        kind: XcircuiteFileKind
    ) throws -> XcircuiteFileReference {
        let url = root.appending(path: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        return XcircuiteFileReference(
            artifactID: name,
            path: name,
            kind: kind,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: data),
            byteCount: Int64(data.count)
        )
    }
}
