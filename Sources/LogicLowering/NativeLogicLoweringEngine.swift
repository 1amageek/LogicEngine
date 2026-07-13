import Foundation
import CircuiteFoundation
import LogicEngineCore
import LogicIR

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
    ) async throws -> LogicLoweringResult {
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
            guard request.design.designRevision?.hexadecimalValue == nil
                || request.design.designRevision?.hexadecimalValue == canonicalDesignDigest else {
                throw LogicExecutionError.artifactDigestMismatch(request.design.artifact.locator.location.value)
            }
            guard snapshot.rtl.topModuleName == request.design.topDesignName else {
                throw LogicExecutionError.invalidDesign(
                    "request top design \(request.design.topDesignName) does not match snapshot \(snapshot.rtl.topModuleName)"
                )
            }
            let lowering = lowerer.lower(snapshot)
            guard lowering.status == .completed, let document = lowering.document else {
                return result(
                    request: request,
                    status: lowering.status,
                    diagnostics: lowering.diagnostics,
                    payload: LogicLoweringPayload(sourceDesignDigest: canonicalDesignDigest),
                    document: nil,
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
            let executionDesignDigest = output.digest.hexadecimalValue
            let designReference = LogicFoundationDesignReference(
                artifact: output,
                topDesignName: document.topDesignName,
                designRevision: try ContentDigest(algorithm: .sha256, hexadecimalValue: executionDesignDigest)
            )
            return result(
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
                document: document,
                startedAt: startedAt
            )
        } catch let error as LogicExecutionError {
            return result(
                request: request,
                status: LogicDiagnosticFactory.status(for: error),
                diagnostics: [LogicDiagnosticFactory.make(for: error)],
                payload: LogicLoweringPayload(),
                document: nil,
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

    private func result(
        request: LogicLoweringRequest,
        status: LogicEngineCore.LogicExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference] = [],
        payload: LogicLoweringPayload,
        document: LogicDesignDocument?,
        startedAt: Date
    ) -> LogicLoweringResult {
        LogicLoweringResult(
            status: status,
            document: document,
            payload: payload,
            artifacts: artifacts,
            diagnostics: diagnostics
        )
    }
}
