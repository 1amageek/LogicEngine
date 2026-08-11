import Foundation
import LogicEngineCore
import LogicIR
import PDKCore
import LogicSynthesis
import TimingCore
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation

struct LogicEngineTestFixture {
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
        try binding(named: name, kind: kind, format: format).reference
    }

    static func binding(
        named name: String,
        kind: ArtifactKind = .other,
        format: ArtifactFormat = .json
    ) throws -> LogicArtifactBinding {
        let url = try url(named: name)
        let data = try Data(contentsOf: url)
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count),
            descriptor: ArtifactDescriptor(role: .input, kind: kind, format: format)
        )
        return try LogicArtifactBinding.local(reference: reference, fileURL: url)
    }

    static func designReference(named name: String = "and-design") throws -> LogicDesignReference {
        let artifact = try reference(named: name, kind: .netlist)
        let topDesignName = name == "and-design" ? "and_top" : "unsupported_top"
        return LogicDesignReference(
            artifact: artifact,
            topDesignName: topDesignName,
            canonicalDesignDigest: artifact.digest
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
        let designBinding = try binding(named: "and-design", kind: .netlist)
        let design = LogicDesignReference(
            artifact: designBinding.reference,
            topDesignName: "and_top",
            canonicalDesignDigest: designBinding.digest
        )
        let libraryBinding = try binding(named: "logic-cells", kind: .timingLibrary, format: .json)
        let timingLibraryBinding = try TimingArtifactBinding(
            reference: libraryBinding.reference,
            availability: timingAvailability(from: libraryBinding.availability)
        )
        let constraintsBinding = try binding(named: "logic-constraints", kind: .constraint, format: .json)
        let pdkBinding = try binding(named: "pdk-manifest", kind: .technology, format: .json)
        return LogicSynthesisRequest(
            runID: "logic-synthesis-fixture",
            inputBindings: [designBinding],
            design: design,
            libraries: [TimingLibraryReference(artifact: timingLibraryBinding, cornerIDs: ["typical"])],
            constraints: constraintsBinding,
            pdk: PDKReference(
                manifest: pdkBinding.reference,
                manifestLocator: try locator(
                    named: "pdk-manifest",
                    kind: .technology,
                    format: .json
                ),
                processID: "logic-fixture",
                version: "1",
                digest: pdkBinding.digest.hexadecimalValue
            ),
            artifactDirectory: outputDirectory?.path(percentEncoded: false)
        )
    }

    static func locator(
        named name: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactLocator {
        ArtifactLocator(
            location: try ArtifactLocation(fileURL: url(named: name)),
            role: .input,
            kind: kind,
            format: format
        )
    }

    static func timingAvailability(
        from availability: ArtifactAvailability
    ) throws -> ArtifactAvailability {
        switch availability {
        case .local(let artifactID, _, let relativePath):
            return .local(
                artifactID: artifactID,
                rootID: try ArtifactRootID(
                    rawValue: TimingArtifactBinding.localFileSystemRootIdentifier
                ),
                relativePath: relativePath
            )
        case .service:
            return availability
        }
    }
}
