import Foundation
import CircuiteFoundation
import LogicEngineCore
import Testing
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation

@Suite("LogicEngine core")
struct LogicCoreTests {
    @Test("four-state truth tables preserve unknown values")
    func truthTables() throws {
        let zero = try LogicVector(string: "0")
        let one = try LogicVector(string: "1")
        let unknown = try LogicVector(string: "X")
        #expect(try LogicVector.and([zero, unknown], width: 1) == zero)
        #expect(try LogicVector.or([one, unknown], width: 1) == one)
        #expect(try LogicVector.and([one, unknown], width: 1) == unknown)
        #expect(try LogicVector.xor([one, unknown], width: 1) == unknown)
        #expect(try LogicVector.merge(zero, one) == unknown)
    }

    @Test("signed vector arithmetic preserves sign extension and two's-complement results")
    func signedArithmetic() throws {
        let negativeTwo = try LogicVector(string: "1110")
        let positiveOne = try LogicVector(string: "01")
        let three = try LogicVector(string: "0011")
        let negativeOne = try LogicVector(string: "1111")
        let negativeFive = try LogicVector(string: "1011")
        let unknown = try LogicVector(string: "XXXX")

        #expect(try LogicVector.signedAdded(negativeTwo, positiveOne, width: 4) == negativeOne)
        #expect(try LogicVector.signedSubtracted(negativeTwo, three, width: 4) == negativeFive)
        #expect(try LogicVector.signedMultiplied(negativeTwo, positiveOne, width: 4) == negativeTwo)
        #expect(try LogicVector.arithmeticShiftedRight(negativeTwo, by: LogicVector(string: "1"), width: 4) == negativeOne)
        #expect(try LogicVector.signedAdded(negativeTwo, LogicVector(string: "0X"), width: 4) == unknown)
    }

    @Test("vector logical truth values preserve four-state short-circuit semantics")
    func vectorLogicalTruthValues() throws {
        let zero = try LogicVector(string: "00")
        let one = try LogicVector(string: "01")
        let unknown = try LogicVector(string: "0X")
        let high = try LogicVector(string: "Z0")

        #expect(LogicVector.logicalAnd(zero, unknown) == LogicVector(.zero))
        #expect(LogicVector.logicalAnd(one, unknown) == LogicVector(.unknown))
        #expect(LogicVector.logicalOr(zero, unknown) == LogicVector(.unknown))
        #expect(LogicVector.logicalOr(one, high) == LogicVector(.one))
        #expect(LogicVector.logicalNot(zero) == LogicVector(.one))
        #expect(LogicVector.logicalNot(one) == LogicVector(.zero))
        #expect(LogicVector.logicalNot(high) == LogicVector(.unknown))
    }

    @Test("design and stimulus schemas round-trip as compact JSON values")
    func schemaRoundTrip() throws {
        let vector = try LogicVector(string: "01XZ")
        let design = LogicDesignDocument(
            topDesignName: "round_trip",
            ports: [LogicPort(name: "a", direction: .input, width: 1)],
            signals: [LogicSignal(name: "a", width: 1)],
            nodes: []
        )
        let stimulus = LogicStimulusDocument(
            events: [LogicStimulusEvent(time: 0, assignments: ["a": vector])]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(stimulus)
        let decoded = try JSONDecoder().decode(LogicStimulusDocument.self, from: data)
        #expect(decoded == stimulus)
        #expect(try JSONDecoder().decode(LogicDesignDocument.self, from: encoder.encode(design)) == design)
    }

    @Test("artifact bindings preserve content identity across relocation and reject availability drift")
    func artifactBindingIdentityAndDescriptorValidation() throws {
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: Data("identity".utf8)),
            byteCount: UInt64(Data("identity".utf8).count),
            descriptor: ArtifactDescriptor(role: .input, kind: .netlist, format: .json)
        )
        let first = try LogicArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(rawValue: LogicArtifactBinding.workspaceRootIdentifier),
                relativePath: try ArtifactRelativePath(segments: ["first", "design.json"])
            )
        )
        let second = try LogicArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(rawValue: LogicArtifactBinding.workspaceRootIdentifier),
                relativePath: try ArtifactRelativePath(segments: ["second", "design.json"])
            )
        )

        #expect(first.reference == second.reference)
        #expect(first.availability != second.availability)
        let otherData = Data("other-content".utf8)
        let otherReference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: otherData),
            byteCount: UInt64(otherData.count),
            descriptor: reference.descriptor
        )
        #expect(throws: LogicArtifactBindingError.availabilityIdentityMismatch) {
            try LogicArtifactBinding(
                reference: reference,
                availability: .local(
                    artifactID: otherReference.id,
                    rootID: try ArtifactRootID(rawValue: LogicArtifactBinding.workspaceRootIdentifier),
                    relativePath: try ArtifactRelativePath(segments: ["design.vcd"])
                )
            )
        }
    }

    @Test("filesystem artifact store reports content tampering as a typed failure")
    func artifactStoreRejectsTamperedContent() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "logic-store-tamper-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary artifact root: \(error)")
            }
        }
        let expected = Data("expected".utf8)
        try Data("tampered".utf8).write(to: root.appending(path: "artifact.json"))
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "artifact.json"),
            role: .input,
            kind: .report,
            format: .json
        )
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: expected),
            byteCount: UInt64(expected.count),
            descriptor: locator.descriptor
        )
        let binding = try LogicArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(rawValue: LogicArtifactBinding.workspaceRootIdentifier),
                relativePath: try ArtifactRelativePath(segments: ["artifact.json"])
            )
        )

        #expect(throws: LogicExecutionError.artifactDigestMismatch("local:logic-workspace/artifact.json")) {
            try FileSystemLogicArtifactStore(rootDirectory: root).read(binding)
        }
    }

    @Test("filesystem artifact store rejects output outside its root")
    func artifactStoreRejectsOutsideRoot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "logic-store-root-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory.appending(path: "logic-store-outside-\(UUID().uuidString)")
        let store = FileSystemLogicArtifactStore(rootDirectory: root)

        #expect(throws: LogicExecutionError.self) {
            try store.write(
                Data("artifact".utf8),
                fileName: "result.json",
                outputDirectory: outside.path(percentEncoded: false),
                runID: "outside-root",
                kind: .report,
                format: .json
            )
        }
    }

    @Test("filesystem artifact store accepts an absolute output inside its configured directory")
    func artifactStoreAcceptsAbsoluteOutputInsideConfiguredDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "logic-store-configured-output-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary artifact root: \(error)")
            }
        }
        let outputDirectory = root.appending(path: "artifacts", directoryHint: .isDirectory)
        let store = FileSystemLogicArtifactStore(
            rootDirectory: root,
            defaultOutputDirectory: outputDirectory
        )

        let reference = try store.write(
            Data("artifact".utf8),
            fileName: "result.json",
            outputDirectory: outputDirectory.path(percentEncoded: false),
            runID: "configured-output",
            kind: .report,
            format: .json
        )

        #expect(
            reference.availability == .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(rawValue: LogicArtifactBinding.workspaceRootIdentifier),
                relativePath: try ArtifactRelativePath(segments: ["artifacts", "result.json"])
            )
        )
        #expect(try store.read(reference) == Data("artifact".utf8))
    }

    @Test("filesystem artifact store reads its configured output root outside the input root")
    func artifactStoreReadsConfiguredExternalOutput() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "logic-store-input-root-\(UUID().uuidString)"
        )
        let output = FileManager.default.temporaryDirectory.appending(
            path: "logic-store-output-root-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
                try FileManager.default.removeItem(at: output)
            } catch {
                Issue.record("Failed to remove temporary artifact roots: \(error)")
            }
        }
        let store = FileSystemLogicArtifactStore(
            rootDirectory: root,
            defaultOutputDirectory: output
        )
        let binding = try store.write(
            Data("artifact".utf8),
            fileName: "result.json",
            outputDirectory: output.path(percentEncoded: false),
            runID: "external-output",
            kind: .report,
            format: .json
        )

        #expect(try store.read(binding) == Data("artifact".utf8))
    }

    @Test("filesystem artifact store rejects absolute and symlinked input outside its root")
    func artifactStoreRejectsInputOutsideRoot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "logic-store-read-root-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory.appending(path: "logic-store-read-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideArtifact = outside.appending(path: "result.json")
        let data = Data("artifact".utf8)
        try data.write(to: outsideArtifact)
        let absoluteLocator = ArtifactLocator(
            location: try ArtifactLocation(fileURL: outsideArtifact),
            role: .input,
            kind: .report,
            format: .json
        )
        let outsideReference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            descriptor: absoluteLocator.descriptor
        )
        let absoluteReference = try LogicArtifactBinding.local(
            reference: outsideReference,
            fileURL: outsideArtifact
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        #expect(throws: LogicExecutionError.self) {
            try store.read(absoluteReference)
        }

        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "escaped.json"),
            withDestinationURL: outsideArtifact
        )
        let symlinkLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "escaped.json"),
            role: .input,
            kind: .report,
            format: .json
        )
        let symlinkArtifactReference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            descriptor: symlinkLocator.descriptor
        )
        let symlinkReference = try LogicArtifactBinding(
            reference: symlinkArtifactReference,
            availability: .local(
                artifactID: symlinkArtifactReference.id,
                rootID: try ArtifactRootID(rawValue: LogicArtifactBinding.workspaceRootIdentifier),
                relativePath: try ArtifactRelativePath(segments: ["escaped.json"])
            )
        )
        #expect(throws: LogicExecutionError.self) {
            try store.read(symlinkReference)
        }
    }

    @Test("filesystem artifact store rejects symlink escapes")
    func artifactStoreRejectsSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "logic-store-symlink-root-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory.appending(path: "logic-store-symlink-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = root.appending(path: "escaped")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)

        #expect(throws: LogicExecutionError.self) {
            try store.write(
                Data("artifact".utf8),
                fileName: "result.json",
                outputDirectory: "escaped",
                runID: "symlink-escape",
                kind: .report,
                format: .json
            )
        }
    }

    @Test("filesystem artifact store is idempotent and rejects immutable collisions")
    func artifactStoreRejectsImmutableCollision() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "logic-store-collision-\(UUID().uuidString)")
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let original = try store.write(
            Data("first".utf8),
            fileName: "result.json",
            outputDirectory: "artifacts",
            runID: "collision",
            kind: .report,
            format: .json
        )
        let repeated = try store.write(
            Data("first".utf8),
            fileName: "result.json",
            outputDirectory: "artifacts",
            runID: "collision",
            kind: .report,
            format: .json
        )
        #expect(original == repeated)

        #expect(throws: LogicExecutionError.self) {
            try store.write(
                Data("second".utf8),
                fileName: "result.json",
                outputDirectory: "artifacts",
                runID: "collision",
                kind: .report,
                format: .json
            )
        }
    }
}
