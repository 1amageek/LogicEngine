import CircuiteFoundation
import Foundation
import Darwin
import LogicEngineCore
import LogicEngineRuntime
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ActualCellArtifactFailureTests {
    private final class FailingStore: LogicArtifactStoring {
        let base: FileSystemLogicArtifactStore
        let writes = Mutex(0)
        init(base: FileSystemLogicArtifactStore) { self.base = base }
        func read(_ binding: LogicArtifactBinding) throws -> Data { try base.read(binding) }
        func write(_ data: Data, fileName: String, outputDirectory: String?, runID: String,
                   kind: ArtifactKind, format: ArtifactFormat) throws -> LogicArtifactBinding {
            let fail = writes.withLock { $0 += 1; return $0 == 3 }
            if fail { throw LogicExecutionError.artifactWriteFailed("Injected third-file failure") }
            return try base.write(data, fileName: fileName, outputDirectory: outputDirectory, runID: runID, kind: kind, format: format)
        }
    }
    @Test func partialSaveNeverPublishesCompletionReceipt() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FailingStore(base: .init(rootDirectory: root)))
        await #expect(throws: LogicRuntimeError.self) { try await engine.execute(request) }
        let directory = root.appending(path: ".logic-engine/runs/actual-runtime")
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "original-bit-v1.json").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "synthesis-receipt-v4.json").path))
    }
    @Test func digestRebindingCannotBlessAnotherCNFOrMissingContradiction() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        for mutation in 0..<3 {
            var certificate = try #require(JSONSerialization.jsonObject(with: store.read(result.payload.proof)) as? [String: Any])
            if mutation == 0 { certificate["variables"] = try #require(certificate["variables"] as? Int) + 1 }
            else { certificate["additions"] = [[1]] }
            let proof = try store.write(JSONSerialization.data(withJSONObject: certificate), fileName: "wrong-proof-\(mutation).json",
                outputDirectory: nil, runID: "tampered", kind: .report, format: .json)
            var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
            if mutation == 2 { receipt["area"] = 0 }
            else { receipt["proof"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(proof)) }
            let rebound = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "wrong-receipt-\(mutation).json",
                outputDirectory: nil, runID: "tampered", kind: .report, format: .json)
            await #expect(throws: (any Error).self) { try await engine.load(rebound, limits: helper.limits()) }
        }
    }
    private final class CountingStore: LogicArtifactStoring {
        let base: FileSystemLogicArtifactStore
        let byteCount = Mutex(UInt64(0))
        init(root: URL) { base = .init(rootDirectory: root) }
        func read(_ binding: LogicArtifactBinding) throws -> Data {
            let data = try base.read(binding)
            byteCount.withLock { $0 += UInt64(data.count) }
            return data
        }
        func write(_ data: Data, fileName: String, outputDirectory: String?, runID: String,
                   kind: ArtifactKind, format: ArtifactFormat) throws -> LogicArtifactBinding {
            try base.write(data, fileName: fileName, outputDirectory: outputDirectory, runID: runID, kind: kind, format: format)
        }
    }
    @Test func completionReceiptReadBudgetIsAdmittedBeforePublication() async throws {
        let helper = ActualCellRuntimeTests(); let baseline = try helper.temporary(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: baseline); try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let store = CountingStore(root: baseline)
        let result = try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store).execute(helper.request(root: baseline))
        let beforeReceiptRead = store.byteCount.withLock { $0 } - result.receipt.byteCount
        let request = try helper.request(root: root, limits: helper.limits(input: beforeReceiptRead + 100))
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        await #expect(throws: (any Error).self) { _ = try await engine.execute(request) }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/actual-runtime/synthesis-receipt-v4.json").path))
    }
    @Test func nonregularArtifactCannotBlockFileRead() throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let binding = try helper.input(Data("library".utf8), name: "pipe.lib", format: .liberty, root: root)
        let path = root.appending(path: "pipe.lib").path
        try FileManager.default.removeItem(atPath: path)
        #expect(Darwin.mkfifo(path, S_IRUSR | S_IWUSR) == 0)
        #expect(throws: LogicExecutionError.self) { _ = try FileSystemLogicArtifactStore(rootDirectory: root).read(binding) }
    }


    @Test func changedFileSizeAndNonregularCollisionAreRejected() throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let binding = try helper.input(Data("exact".utf8), name: "input.lib", format: .liberty, root: root)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        #expect(try store.read(binding) == Data("exact".utf8))
        for bytes in [Data("x".utf8), Data("oversized".utf8)] {
            try bytes.write(to: root.appending(path: "input.lib"))
            #expect(throws: LogicExecutionError.self) { _ = try store.read(binding) }
        }
        let artifact = try store.write(Data("first".utf8), fileName: "existing.json", outputDirectory: nil,
            runID: "collision", kind: .report, format: .json)
        #expect(throws: LogicExecutionError.self) {
            _ = try store.write(Data("longer".utf8), fileName: "existing.json", outputDirectory: nil,
                runID: "collision", kind: .report, format: .json)
        }
        let destination = try artifact.localFileURL(relativeTo: root, outputRoot: nil)
        #expect(try Data(contentsOf: destination) == Data("first".utf8))
        try FileManager.default.removeItem(at: destination)
        #expect(Darwin.mkfifo(destination.path, S_IRUSR | S_IWUSR) == 0)
        #expect(throws: LogicExecutionError.self) {
            _ = try store.write(Data("first".utf8), fileName: "existing.json", outputDirectory: nil,
                runID: "collision", kind: .report, format: .json)
        }
    }
}
