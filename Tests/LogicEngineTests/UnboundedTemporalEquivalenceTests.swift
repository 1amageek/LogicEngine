import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicSynthesis
import Testing

@Suite("Unbounded temporal equivalence")
struct UnboundedTemporalEquivalenceTests {
    @Test("exhaustively proves a combinational relation and persists a certificate")
    func provesCombinationalRelation() async throws {
        let root = try makeRoot(name: "unbounded-proof")
        defer { removeRoot(root) }
        let design = makeAndDesign(name: "formal_top")
        let reference = try writeJSON(design, name: "reference.json", root: root, kind: .netlist)
        let implementation = try writeJSON(design, name: "implementation.json", root: root, kind: .netlist)
        let request = try makeRequest(
            runID: "unbounded-proof",
            reference: reference,
            implementation: implementation,
            topName: "formal_top",
            outputSignals: ["y"]
        )

        let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.proofStatus == .proved)
        #expect(result.payload.exploredStateCount == 1)
        #expect(result.payload.exploredTransitionCount == 4)
        let reportReference = try #require(result.payload.equivalenceReport)
        let certificateReference = try #require(result.payload.proofCertificate)
        let reportData = try readFoundationArtifact(reportReference, root: root)
        let certificateData = try readFoundationArtifact(certificateReference, root: root)
        let report = try JSONDecoder().decode(LogicUnboundedTemporalEquivalenceReport.self, from: reportData)
        let certificate = try JSONDecoder().decode(
            LogicUnboundedTemporalEquivalenceCertificate.self,
            from: certificateData
        )
        try report.validate()
        try certificate.validateBinding(
            requestDigest: report.requestDigest,
            reportDigest: try SHA256ContentDigester()
                .digest(data: reportData, using: .sha256)
                .hexadecimalValue
        )
        #expect(certificate.complete)
    }

    @Test("persists an exhaustive counterexample")
    func persistsCounterexample() async throws {
        let root = try makeRoot(name: "unbounded-counterexample")
        defer { removeRoot(root) }
        let referenceDesign = makeBufferDesign(name: "formal_top")
        let implementationDesign = makeConstantDesign(name: "formal_top", value: "0")
        let reference = try writeJSON(referenceDesign, name: "reference.json", root: root, kind: .netlist)
        let implementation = try writeJSON(implementationDesign, name: "implementation.json", root: root, kind: .netlist)
        let request = try makeRequest(
            runID: "unbounded-counterexample",
            reference: reference,
            implementation: implementation,
            topName: "formal_top",
            outputSignals: ["y"]
        )

        let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .failed)
        #expect(result.payload.proofStatus == .counterexample)
        #expect(result.payload.counterexample != nil)
        #expect(result.payload.proofCertificate == nil)
        #expect(result.diagnostics.contains { $0.code.rawValue.lowercased().contains("counterexample") })
    }

    @Test("blocks a relation whose finite input space exceeds the declared limit")
    func blocksOversizedRelation() async throws {
        let root = try makeRoot(name: "unbounded-limit")
        defer { removeRoot(root) }
        let design = makeBufferDesign(name: "formal_top", width: 3)
        let reference = try writeJSON(design, name: "reference.json", root: root, kind: .netlist)
        let implementation = try writeJSON(design, name: "implementation.json", root: root, kind: .netlist)
        var request = try makeRequest(
            runID: "unbounded-limit",
            reference: reference,
            implementation: implementation,
            topName: "formal_top",
            outputSignals: ["y"]
        )
        request = LogicUnboundedTemporalEquivalenceFoundationRequest(
            runID: request.runID,
            referenceDesign: request.referenceDesign,
            implementationDesign: request.implementationDesign,
            outputSignals: request.outputSignals,
            valueDomain: request.valueDomain,
            stateSpaceLimit: 1,
            transitionLimit: 4,
            timeoutNanoseconds: request.timeoutNanoseconds,
            inputs: request.inputs,
            artifactDirectory: request.artifactDirectory
        )

        let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == LogicExecutionStatus.blocked)
        #expect(result.payload.proofStatus == LogicUnboundedTemporalEquivalenceStatus.blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue.lowercased().contains("prerequisite") })
    }

    @Test("covers sequential state and clock contexts without a trace bound")
    func provesSequentialRelation() async throws {
        let root = try makeRoot(name: "unbounded-sequential")
        defer { removeRoot(root) }
        let design = makeDFFDesign(name: "formal_top")
        let reference = try writeJSON(design, name: "reference.json", root: root, kind: .netlist)
        let implementation = try writeJSON(design, name: "implementation.json", root: root, kind: .netlist)
        let request = try makeRequest(
            runID: "unbounded-sequential",
            reference: reference,
            implementation: implementation,
            topName: "formal_top",
            outputSignals: ["q"],
            clockSignal: "clk",
            stateSpaceLimit: 2,
            transitionLimit: 16
        )

        let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.proofStatus == .proved)
        #expect(result.payload.exploredStateCount == 2)
        #expect(result.payload.exploredTransitionCount == 16)
    }

    @Test("covers level-sensitive state contexts without inventing a clock")
    func provesLatchRelation() async throws {
        let root = try makeRoot(name: "unbounded-latch")
        defer { removeRoot(root) }
        let design = makeLatchDesign(name: "formal_top")
        let reference = try writeJSON(design, name: "reference.json", root: root, kind: .netlist)
        let implementation = try writeJSON(design, name: "implementation.json", root: root, kind: .netlist)
        let request = try makeRequest(
            runID: "unbounded-latch",
            reference: reference,
            implementation: implementation,
            topName: "formal_top",
            outputSignals: ["q"],
            stateSpaceLimit: 2,
            transitionLimit: 8
        )

        let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.proofStatus == .proved)
        #expect(result.payload.exploredStateCount == 2)
        #expect(result.payload.exploredTransitionCount == 8)
    }

    @Test("exhausts the declared four-state combinational domain")
    func provesFourStateRelation() async throws {
        let root = try makeRoot(name: "unbounded-four-state")
        defer { removeRoot(root) }
        let design = makeBufferDesign(name: "formal_top")
        let reference = try writeJSON(design, name: "reference.json", root: root, kind: .netlist)
        let implementation = try writeJSON(design, name: "implementation.json", root: root, kind: .netlist)
        let request = try makeRequest(
            runID: "unbounded-four-state",
            reference: reference,
            implementation: implementation,
            topName: "formal_top",
            outputSignals: ["y"],
            valueDomain: .fourState,
            transitionLimit: 4
        )

        let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.proofStatus == .proved)
        #expect(result.payload.exploredTransitionCount == 4)
    }

    @Test("returns a structured timeout rather than claiming a proof")
    func timesOutExhaustiveRelation() async throws {
        let root = try makeRoot(name: "unbounded-timeout")
        defer { removeRoot(root) }
        let design = makeBufferDesign(name: "formal_top", width: 10)
        let reference = try writeJSON(design, name: "reference.json", root: root, kind: .netlist)
        let implementation = try writeJSON(design, name: "implementation.json", root: root, kind: .netlist)
        let request = try makeRequest(
            runID: "unbounded-timeout",
            reference: reference,
            implementation: implementation,
            topName: "formal_top",
            outputSignals: ["y"],
            transitionLimit: 1_024,
            timeoutNanoseconds: 1
        )

        let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == LogicExecutionStatus.blocked)
        #expect(result.payload.proofStatus == LogicUnboundedTemporalEquivalenceStatus.timeout)
        #expect(result.diagnostics.contains { $0.code.rawValue.lowercased().contains("timeout") })
    }

    @Test("certificate binding rejects tampered report identity")
    func rejectsTamperedCertificateBinding() throws {
        let certificate = LogicUnboundedTemporalEquivalenceCertificate(
            requestDigest: "request",
            reportDigest: "report",
            solverID: "native-exhaustive-finite-state",
            solverVersion: "1",
            proofScope: "native-exhaustive-finite-state-v1",
            valueDomain: .twoState,
            exploredStateCount: 1,
            exploredTransitionCount: 1,
            complete: true,
            status: .proved
        )

        #expect(throws: LogicExecutionError.self) {
            try certificate.validateBinding(requestDigest: "request", reportDigest: "tampered")
        }
    }

    private func makeRequest(
        runID: String,
        reference: ArtifactReference,
        implementation: ArtifactReference,
        topName: String,
        outputSignals: [String],
        valueDomain: LogicUnboundedTemporalEquivalenceDomain = .twoState,
        clockSignal: String? = nil,
        stateSpaceLimit: Int = 1,
        transitionLimit: Int = 4,
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) throws -> LogicUnboundedTemporalEquivalenceFoundationRequest {
        return LogicUnboundedTemporalEquivalenceFoundationRequest(
            runID: runID,
            referenceDesign: LogicFoundationDesignReference(
                artifact: reference,
                topDesignName: topName
            ),
            implementationDesign: LogicFoundationDesignReference(
                artifact: implementation,
                topDesignName: topName
            ),
            outputSignals: outputSignals,
            valueDomain: valueDomain,
            stateSpaceLimit: stateSpaceLimit,
            transitionLimit: transitionLimit,
            timeoutNanoseconds: timeoutNanoseconds,
            clockSignal: clockSignal,
            inputs: [reference, implementation],
            artifactDirectory: "outputs"
        )
    }

    private func makeAndDesign(name: String) -> LogicDesignDocument {
        LogicDesignDocument(
            topDesignName: name,
            ports: [
                LogicPort(name: "a", direction: .input),
                LogicPort(name: "b", direction: .input),
                LogicPort(name: "y", direction: .output),
            ],
            signals: [LogicSignal(name: "a"), LogicSignal(name: "b"), LogicSignal(name: "y")],
            nodes: [LogicNode(id: "and", kind: .and, inputs: ["a", "b"], outputs: ["y"])]
        )
    }

    private func makeBufferDesign(name: String, width: Int = 1) -> LogicDesignDocument {
        LogicDesignDocument(
            topDesignName: name,
            ports: [
                LogicPort(name: "a", direction: .input, width: width),
                LogicPort(name: "y", direction: .output, width: width),
            ],
            signals: [LogicSignal(name: "a", width: width), LogicSignal(name: "y", width: width)],
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
            signals: [LogicSignal(name: "a"), LogicSignal(name: "y")],
            nodes: [LogicNode(
                id: "constant",
                kind: .constant,
                inputs: [],
                outputs: ["y"],
                parameters: ["value": value]
            )]
        )
    }

    private func makeDFFDesign(name: String) -> LogicDesignDocument {
        LogicDesignDocument(
            topDesignName: name,
            ports: [
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "clk", direction: .input),
                LogicPort(name: "q", direction: .output),
            ],
            signals: [
                LogicSignal(name: "d"),
                LogicSignal(name: "clk"),
                LogicSignal(name: "q", initialValue: LogicVector(.zero)),
            ],
            nodes: [LogicNode(
                id: "dff",
                kind: .dff,
                inputs: ["d", "clk"],
                outputs: ["q"],
                parameters: ["edge": "positive"]
            )]
        )
    }

    private func makeLatchDesign(name: String) -> LogicDesignDocument {
        LogicDesignDocument(
            topDesignName: name,
            ports: [
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "en", direction: .input),
                LogicPort(name: "q", direction: .output),
            ],
            signals: [
                LogicSignal(name: "d"),
                LogicSignal(name: "en"),
                LogicSignal(name: "q", initialValue: LogicVector(.zero)),
            ],
            nodes: [LogicNode(
                id: "latch",
                kind: .latch,
                inputs: ["d", "en"],
                outputs: ["q"],
                parameters: ["level": "positive"]
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
            Issue.record("Failed to remove unbounded equivalence root: \(error)")
        }
    }

    private func writeJSON<T: Encodable>(
        _ value: T,
        name: String,
        root: URL,
        kind: ArtifactKind
    ) throws -> ArtifactReference {
        let url = root.appending(path: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        return ArtifactReference(
            id: try ArtifactID(rawValue: name),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: name),
                role: .input,
                kind: kind,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count)
        )
    }

    private func readFoundationArtifact(_ reference: ArtifactReference, root: URL) throws -> Data {
        let path = reference.locator.location.value
        return try Data(contentsOf: root.appending(path: path))
    }
}
