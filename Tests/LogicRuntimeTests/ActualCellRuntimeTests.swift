import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import LogicEngineCore
import LogicEngineRuntime
import LogicIR
import LogicKernelCore
import LogicProof
import LogicSimulation
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ActualCellRuntimeTests {
    static let liberty = """
    library(L){cell(AND){area:2;pin(B){direction:input;}pin(Z){direction:output;function:"A B";}pin(A){direction:input;}}
    cell(INV){area:1;pin(Z){direction:output;function:"!A";}pin(A){direction:input;}}
    cell(FF){area:3;ff(S,SN){next_state:"D";clocked_on:"C";clear:"!RN";}pin(Q){direction:output;function:"S";}
    pin(D){direction:input;}pin(C){direction:input;}pin(RN){direction:input;}}
    cell(LATCH){area:3;latch(S,SN){data_in:"D";enable:"G";}pin(Q){direction:output;function:"S";}pin(D){direction:input;}pin(G){direction:input;}}}
    """
    func limits(work: UInt64 = 1_000_000_000, output: UInt64 = 10_000_000, timeout: UInt64 = 10_000_000_000, input: UInt64 = 50_000_000, tokens: Int = 10_000, tables: Int = 500, nesting: Int = 64) -> LogicRuntimeLimits {
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0.rawValue, UInt64(1_000_000_000)) })
        maximums[LogicResource.workUnits.rawValue] = work
        return .init(kernelMaximums: maximums, maximumInputBytes: input, maximumOutputBytes: output,
            timeoutNanoseconds: timeout, maximumTokens: tokens, maximumTableEntries: tables,
            maximumNesting: nesting, maximumCutInputs: 3, maximumCellInputs: 4, maximumCutsPerNode: 8,
            firstLibraryEntityID: 100_000, firstMappedEntityID: 1_000_000)
    }
    func input(_ data: Data, name: String, format: ArtifactFormat, root: URL) throws -> LogicArtifactBinding {
        let url = root.appending(path: name); try data.write(to: url)
        return try .local(reference: .init(digest: SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count), descriptor: .init(role: .input, kind: .rtl, format: format)), fileURL: url)
    }
    func request(root: URL, source: String = "module top(input [7:0] a,b,output [7:0] y);assign y=a&b;endmodule",
                 limits: LogicRuntimeLimits? = nil, constraints: LogicSynthesisConstraints = .init()) throws -> LogicEngineRuntime.LogicSynthesisRequest {
        let source = try input(Data(source.utf8), name: "top.sv", format: .systemVerilog, root: root)
        let library = try input(Data(Self.liberty.utf8), name: "cells.lib", format: .liberty, root: root)
        return .init(runID: "actual-runtime", sources: [.init(logicalName: "top.sv", artifact: source)],
            roots: ["top.sv"], top: "top", library: library, limits: limits ?? self.limits(), constraints: constraints)
    }
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "logic-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func apiSourceToActualVerilogProofSaveAndCheckedReload() async throws {
        let root = try temporary(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let concrete = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
        let engine: any LogicEngineRuntime.LogicSynthesisExecuting = concrete
        let result = try await engine.execute(request)
        #expect(result.status == .completed && result.payload.instanceCount == 8 && result.payload.area == 16)
        #expect(result.payload.combinationalDepth == 1 && result.payload.proofKind == "combinational-rup")
        #expect(result.evidence.provenance.inputs == request.inputs)
        let loader: any LogicSynthesisArtifactLoading = concrete
        let verified = try await loader.load(result.receipt, limits: request.limits)
        try verified.equivalence.requireBinding(to: verified.problem)
        #expect(verified.mapped.instanceCount == 8)
        let source = String(decoding: try store.read(result.payload.netlist), as: UTF8.self)
        #expect(source.contains("\\AND ") && source.contains(".\\Z "))
        let original = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisResult.self, from: JSONEncoder().encode(result))
        #expect(original == result)
    }
    @Test func ffAndLatchSourcePreserveUnspecifiedStartupThroughReload() async throws {
        for source in ["module top(input c,rn,d,output logic q);always_ff @(posedge c or negedge rn) if(!rn)q<=0;else q<=d;endmodule",
                       "module top(input g,d,output logic q);always_latch if(g)q=d;endmodule"] {
            let root = try temporary(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, source: source)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
            let result = try await engine.execute(request)
            let verified = try await engine.load(result.receipt, limits: request.limits)
            #expect(verified.mapped.stateCount == 1 && result.payload.proofKind == "state-preserving-induction-rup")
            #expect(verified.mapped.withTables { _, instances, _, _, _, _ in instances[0].initialValue == nil })
        }
    }
    @Test func sourceInitializationRemainsObservableButCannotBecomePhysicalStartup() async throws {
        for (declaration, expected) in [("bit q", "0"), ("logic q=1'b0", "0"), ("bit q=1'b1", "1")] {
            let root = try temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, source: "module top(input c,rn,d,output \(declaration));always_ff @(posedge c or negedge rn) if(!rn)q<=0;else q<=d;endmodule")
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let observed = try await LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store).execute(
                .init(runID: "abstract-startup", sources: request.sources, roots: request.roots, top: request.top,
                      events: [], limits: request.limits))
            #expect(observed.observations[0].outputs[0].value == expected)
            await #expect(throws: LogicRuntimeError.self) {
                try await LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store).execute(request)
            }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/actual-runtime/synthesis-receipt-v4.json").path))
        }
    }
    @Test func requiredAreaAndUnknownPowerCannotPublishCompletedReceipt() async throws {
        for constraints in [LogicSynthesisConstraints(maximumArea: 1), .init(maximumPower: 0)] {
            let root = try temporary(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, constraints: constraints)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
            await #expect(throws: LogicRuntimeError.self) { try await engine.execute(request) }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/actual-runtime/synthesis-receipt-v4.json").path))
        }
    }
    @Test func cumulativeWorkOutputDeadlineAndCancellationRemainFailures() async throws {
        for limits in [limits(work: 20), limits(output: 1), limits(timeout: 1)] {
            let root = try temporary(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root, limits: limits)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
            await #expect(throws: (any Error).self) { try await engine.execute(request) }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/actual-runtime/synthesis-receipt-v4.json").path))
        }
        let root = try temporary(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let task = Task { try await engine.execute(request) }; task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
    @Test func changedSourceOrCertificateFailsVerifiedReload() async throws {
        for changeSource in [true, false] {
            let root = try temporary(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try request(root: root)
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
            let result = try await engine.execute(request)
            let binding = changeSource ? request.sources[0].artifact : result.payload.proof
            let url = try binding.localFileURL(relativeTo: root, outputRoot: nil)
            try Data("corrupted".utf8).write(to: url)
            await #expect(throws: (any Error).self) { try await engine.load(result.receipt, limits: request.limits) }
        }
    }
    @Test func missingOrOldSchemaCannotBecomeAnActualCellResult() async throws {
        let root = try temporary(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        object["schemaVersion"] = ["major": 3, "minor": 0, "patch": 0]
        let old = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisRequest.self, from: JSONSerialization.data(withJSONObject: object))
        await #expect(throws: LogicKernelError.self) { try await engine.execute(old) }
        try FileManager.default.removeItem(at: root.appending(path: "cells.lib"))
        await #expect(throws: LogicRuntimeError.self) { try await engine.execute(request) }
    }
    @Test func reloadAndMappedSimulationHonorCallerParseCaps() async throws {
        let root = try temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try request(root: root)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
        let result = try await engine.execute(request)
        for caps in [limits(tokens: 1), limits(tables: 1), limits(nesting: 1)] {
            await #expect(throws: (any Error).self) { _ = try await engine.load(result.receipt, limits: caps) }
            let simulation = LogicEngineRuntime.LogicSimulationRequest(runID: "strict-replay", mappedReceipt: result.receipt,
                events: [], limits: caps)
            await #expect(throws: (any Error).self) {
                _ = try await LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store).execute(simulation)
            }
        }
    }

}
