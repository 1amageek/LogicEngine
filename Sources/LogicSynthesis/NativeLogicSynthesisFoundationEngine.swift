import LogicEngineCore
import LogicIR
import PDKCore
import PowerIntent
import TimingCore
import XcircuitePackage

/// Package-owned compatibility boundary for the existing native synthesizer.
public struct NativeLogicSynthesisFoundationEngine: LogicSynthesisFoundationEngine {
    public let legacyEngine: any LogicSynthesisExecuting

    public init(
        legacyEngine: any LogicSynthesisExecuting = NativeLogicSynthesisEngine()
    ) {
        self.legacyEngine = legacyEngine
    }

    public func execute(
        _ request: LogicSynthesisFoundationRequest
    ) async throws -> LogicSynthesisFoundationResult {
        try request.validate()
        let bridge = LogicFoundationArtifactBridge()
        let designArtifact = try bridge.legacyReference(
            from: request.design.artifact,
            runID: request.runID,
            kind: .netlist,
            format: .json
        )
        let libraries = try request.libraries.map { library in
            TimingLibraryReference(
                artifact: try bridge.legacyReference(
                    from: library.artifact,
                    runID: request.runID,
                    kind: .timingLibrary,
                    format: .liberty
                ),
                cornerIDs: library.cornerIDs
            )
        }
        let constraintsArtifact = try bridge.legacyReference(
            from: request.constraints,
            runID: request.runID,
            kind: .constraint,
            format: .sdc
        )
        let pdkArtifact = try bridge.legacyReference(
            from: request.pdkManifest,
            runID: request.runID,
            kind: .technology,
            format: .json
        )
        let powerIntent = try request.powerIntent.map {
            PowerIntentReference(
                artifact: try bridge.legacyReference(
                    from: $0,
                    runID: request.runID,
                    kind: .powerIntent,
                    format: .upf
                ),
                designDigest: request.powerIntentDesignRevision?.hexadecimalValue
                    ?? request.design.artifact.digest.hexadecimalValue
            )
        }
        let legacyInputs = try request.inputs.map {
            try bridge.legacyReference(from: $0, runID: request.runID)
        }
        let legacyRequest = LogicSynthesisRequest(
            runID: request.runID,
            inputs: legacyInputs,
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: request.design.topDesignName,
                designDigest: request.design.designRevision?.hexadecimalValue
                    ?? request.design.artifact.digest.hexadecimalValue
            ),
            libraries: libraries,
            constraints: TimingConstraintReference(
                artifact: constraintsArtifact,
                modeIDs: request.constraintModeIDs
            ),
            pdk: PDKReference(
                manifest: pdkArtifact,
                processID: request.processID,
                version: request.pdkVersion,
                digest: request.pdkDigest.hexadecimalValue
            ),
            powerIntent: powerIntent,
            artifactDirectory: request.artifactDirectory
        )
        let legacyResult = try await legacyEngine.execute(legacyRequest)
        return try LogicSynthesisFoundationResult(
            legacy: legacyResult,
            request: request
        )
    }
}
