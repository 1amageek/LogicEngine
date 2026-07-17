import Foundation
import CircuiteFoundation
import LogicEngineCore
import Testing

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

    @Test("design signals default omitted signedness to unsigned")
    func legacySignalSignednessDefaultsToUnsigned() throws {
        let data = Data(
            "{\"schemaVersion\":1,\"topDesignName\":\"legacy\",\"ports\":[],\"signals\":[{\"name\":\"a\",\"width\":1}],\"nodes\":[],\"metadata\":{}}".utf8
        )
        let design = try JSONDecoder().decode(LogicDesignDocument.self, from: data)

        #expect(design.signals == [LogicSignal(name: "a", width: 1, isSigned: false)])
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
                artifactID: nil,
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
            artifactID: "configured-output-result",
            kind: .report,
            format: .json
        )

        #expect(reference.path == "artifacts/result.json")
        #expect(try store.read(reference) == Data("artifact".utf8))
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
        let absoluteReference = ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(fileURL: outsideArtifact),
                role: .input,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        #expect(throws: LogicExecutionError.self) {
            try store.read(absoluteReference)
        }

        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "escaped.json"),
            withDestinationURL: outsideArtifact
        )
        let symlinkReference = ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "escaped.json"),
                role: .input,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
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
                artifactID: nil,
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
            artifactID: "immutable-result",
            kind: .report,
            format: .json
        )
        let repeated = try store.write(
            Data("first".utf8),
            fileName: "result.json",
            outputDirectory: "artifacts",
            runID: "collision",
            artifactID: "immutable-result",
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
                artifactID: "immutable-result",
                kind: .report,
                format: .json
            )
        }
    }
}
