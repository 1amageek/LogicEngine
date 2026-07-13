import Foundation
import LogicEngineCore
import LogicIR
import PDKCore
import LogicSynthesis
import TimingCore
import CircuiteFoundation

struct LogicEngineTestFixture {
    static func workspaceRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    static func url(named name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw LogicExecutionError.missingArtifact(name)
        }
        return url
    }

    static func reference(
        named name: String,
        kind: ArtifactKind = .other,
        format: ArtifactFormat = .json
    ) throws -> ArtifactReference {
        let url = try url(named: name)
        let data = try Data(contentsOf: url)
        let locator = ArtifactLocator(
            location: try ArtifactLocation(fileURL: url),
            role: .input,
            kind: kind,
            format: format
        )
        return ArtifactReference(
            id: try ArtifactID(rawValue: name),
            locator: locator,
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count)
        )
    }

    static func designReference(named name: String = "and-design") throws -> LogicFoundationDesignReference {
        let artifact = try reference(named: name, kind: .netlist)
        let topDesignName = name == "and-design" ? "and_top" : "unsupported_top"
        return LogicFoundationDesignReference(
            artifact: artifact,
            topDesignName: topDesignName,
            designRevision: artifact.digest
        )
    }

    static func temporaryOutputDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "logic-engine-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func synthesisRequest(outputDirectory: URL? = nil) throws -> LogicSynthesisRequest {
        let design = try designReference()
        let libraryArtifact = try reference(named: "logic-cells", kind: .timingLibrary, format: .json)
        let constraintsArtifact = try reference(named: "logic-constraints", kind: .constraint, format: .json)
        let pdkArtifact = try reference(named: "pdk-manifest", kind: .technology, format: .json)
        return LogicSynthesisRequest(
            runID: "logic-synthesis-fixture",
            inputs: [design.artifact, libraryArtifact, constraintsArtifact, pdkArtifact],
            design: design,
            libraries: [TimingLibraryReference(artifact: libraryArtifact, cornerIDs: ["typical"])],
            constraints: TimingConstraintReference(artifact: constraintsArtifact, modeIDs: ["default"]),
            pdk: PDKReference(manifest: pdkArtifact, processID: "logic-fixture", version: "1", digest: pdkArtifact.sha256),
            artifactDirectory: outputDirectory?.path(percentEncoded: false)
        )
    }
}
