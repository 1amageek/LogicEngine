import Foundation
import LogicEngineCore
import LogicIR
import XcircuitePackage

public struct NativeLogicLoweringEngine: LogicLoweringExecuting {
    public let artifactStore: any LogicArtifactStoring
    public let lowerer: any LogicDesignLowering
    public let implementationVersion: String

    public init(
        artifactStore: any LogicArtifactStoring = FileSystemLogicArtifactStore(),
        lowerer: any LogicDesignLowering = NativeLogicDesignLowering(),
        implementationVersion: String = "1"
    ) {
        self.artifactStore = artifactStore
        self.lowerer = lowerer
        self.implementationVersion = implementationVersion
    }

    public func execute(
        _ request: LogicLoweringRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicLoweringPayload> {
        let startedAt = Date()
        do {
            try validate(request)
            for input in request.inputs {
                _ = try artifactStore.read(input)
            }
            let snapshotData = try artifactStore.read(request.design.artifact)
            let snapshot: LogicDesignSnapshot
            do {
                snapshot = try LogicDesignSnapshotCodec.decode(snapshotData)
            } catch {
                throw LogicExecutionError.invalidArtifact("RTL snapshot JSON could not be decoded: \(error.localizedDescription)")
            }
            let canonicalDesignDigest = try LogicDesignSnapshotCodec.digest(snapshot)
            guard request.design.designDigest.isEmpty
                || request.design.designDigest == canonicalDesignDigest else {
                throw LogicExecutionError.artifactDigestMismatch(request.design.artifact.path)
            }
            guard snapshot.rtl.topModuleName == request.design.topDesignName else {
                throw LogicExecutionError.invalidDesign(
                    "request top design \(request.design.topDesignName) does not match snapshot \(snapshot.rtl.topModuleName)"
                )
            }
            let lowering = lowerer.lower(snapshot)
            guard lowering.status == .completed, let document = lowering.document else {
                return envelope(
                    request: request,
                    status: lowering.status,
                    diagnostics: lowering.diagnostics,
                    payload: LogicLoweringPayload(sourceDesignDigest: canonicalDesignDigest),
                    startedAt: startedAt
                )
            }
            let documentData = try encode(document)
            let output = try artifactStore.write(
                documentData,
                fileName: "logic-execution-design.json",
                outputDirectory: request.artifactDirectory,
                runID: request.runID,
                artifactID: "logic-execution-design",
                kind: .netlist,
                format: .json
            )
            let executionDesignDigest = output.sha256 ?? XcircuiteHasher().sha256(data: documentData)
            let designReference = LogicDesignReference(
                artifact: output,
                topDesignName: document.topDesignName,
                designDigest: executionDesignDigest,
                provenance: LogicDesignProvenance(
                    sourceDesignDigest: canonicalDesignDigest,
                    inputDesignDigest: canonicalDesignDigest,
                    transformationID: "native-rtl-to-execution-graph",
                    producerID: "LogicLowering",
                    producerVersion: implementationVersion,
                    runID: request.runID
                )
            )
            return envelope(
                request: request,
                status: .completed,
                diagnostics: lowering.diagnostics,
                artifacts: [output],
                payload: LogicLoweringPayload(
                    sourceDesignDigest: canonicalDesignDigest,
                    executionDesign: designReference,
                    loweredSignalCount: document.signals.count,
                    loweredNodeCount: document.nodes.count
                ),
                startedAt: startedAt
            )
        } catch let error as LogicExecutionError {
            return envelope(
                request: request,
                status: LogicDiagnosticFactory.status(for: error),
                diagnostics: [LogicDiagnosticFactory.make(for: error)],
                payload: LogicLoweringPayload(),
                startedAt: startedAt
            )
        } catch {
            throw error
        }
    }

    private func validate(_ request: LogicLoweringRequest) throws {
        guard request.schemaVersion == LogicLoweringRequest.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact("unsupported lowering request schema version \(request.schemaVersion)")
        }
        guard !request.runID.isEmpty else {
            throw LogicExecutionError.invalidArtifact("run ID is empty")
        }
        guard !request.design.topDesignName.isEmpty else {
            throw LogicExecutionError.invalidDesign("top design name is empty")
        }
    }

    private func encode(_ document: LogicDesignDocument) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(document)
        } catch {
            throw LogicExecutionError.artifactWriteFailed("execution design encoding failed: \(error.localizedDescription)")
        }
    }

    private func envelope(
        request: LogicLoweringRequest,
        status: XcircuiteEngineExecutionStatus,
        diagnostics: [XcircuiteEngineDiagnostic],
        artifacts: [XcircuiteFileReference] = [],
        payload: LogicLoweringPayload,
        startedAt: Date
    ) -> XcircuiteEngineResultEnvelope<LogicLoweringPayload> {
        XcircuiteEngineResultEnvelope(
            schemaVersion: LogicLoweringRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "LogicLowering",
                implementationID: "native-rtl-to-execution-graph",
                implementationVersion: implementationVersion,
                startedAt: startedAt,
                completedAt: Date()
            ),
            payload: payload
        )
    }
}
