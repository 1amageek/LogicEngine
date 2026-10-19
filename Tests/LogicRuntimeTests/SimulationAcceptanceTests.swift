import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicEngineRuntime
import LogicKernelCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SimulationAcceptanceTests {
    func request(root: URL, runID: String = "acceptance", source: String = "module top(input logic a,output logic y,output wire z,output logic u);assign y=a;endmodule",
                 events: [LogicSimulationEventRecord] = [.init(time: 0, updates: [.init(portIndex: 0, value: "1")])]) throws -> LogicSimulationRequest {
        let helper = ActualCellRuntimeTests()
        let source = try helper.input(Data(source.utf8), name: "top.sv", format: .systemVerilog, root: root)
        return .init(runID: runID, sources: [.init(logicalName: "top.sv", artifact: source)],
                     roots: ["top.sv"], top: "top", events: events, limits: helper.limits())
    }
    func specified(_ request: LogicSimulationRequest, root: URL,
                   assertions: [LogicSimulationSpecification.Assertion]) throws -> LogicSimulationRequest {
        let specification = LogicSimulationSpecification(designInputs: request.designInputs,
            logicalSourceNames: request.sources.map(\.logicalName), roots: request.roots, top: request.top,
            events: request.events, assertions: assertions)
        let binding = try FileSystemLogicArtifactStore(rootDirectory: root).write(JSONEncoder().encode(specification),
            fileName: "specification-\(UUID().uuidString).json", outputDirectory: nil, runID: "specification", kind: .request, format: .json)
        return .init(runID: request.runID, sources: request.sources, roots: request.roots, top: request.top,
            mappedReceipt: request.mappedReceipt, specification: binding, events: request.events, limits: request.limits)
    }
    @Test func exactFourStateAssertionsRetainAcceptanceAndReplayThroughProtocol() async throws {
        let root = try ActualCellRuntimeTests().temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try specified(request(root: root), root: root, assertions: [
            .init(id: "initial-x", observationIndex: 0, time: 0, portIndex: 3, expectedValue: "X"),
            .init(id: "initial-z", observationIndex: 0, time: 0, portIndex: 2, expectedValue: "Z"),
            .init(id: "same-time-next-event", observationIndex: 1, time: 0, portIndex: 1, expectedValue: "1")])
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let concrete = NativeLogicSimulationEngine(artifactStore: store)
        let engine: any LogicSimulationExecuting = concrete
        let result = try await engine.execute(request)
        #expect(result.status == .completed && result.assessment.status == .passed)
        try result.assessment.requirePassed()
        #expect(result.assessment.checkedAssertionCount == 3 && result.assessment.violations.isEmpty)
        #expect(Set(result.provenance.inputs) == Set(request.inputs))
        #expect(result.artifacts.contains(result.acceptance.reference))
        let loader: any LogicSimulationArtifactLoading = concrete
        let saved = try await loader.load(result.acceptance, expectedRequest: request, limits: request.limits)
        #expect(saved.assessment == result.assessment && saved.specification == request.specification
            && saved.operationalInputs == result.provenance.inputs
            && saved.operationalInputBindings.map(\.reference) == saved.operationalInputs)
        #expect(try JSONDecoder().decode(LogicSimulationResult.self, from: JSONEncoder().encode(result)) == result)
    }
    @Test func violationsDistinguishLiteralUnknownWidthsMissingOutputsAndTimes() async throws {
        let root = try ActualCellRuntimeTests().temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try specified(request(root: root), root: root, assertions: [
            .init(id: "x-is-not-zero", observationIndex: 0, time: 0, portIndex: 3, expectedValue: "0"),
            .init(id: "z-is-not-x", observationIndex: 0, time: 0, portIndex: 2, expectedValue: "x"),
            .init(id: "width", observationIndex: 1, time: 0, portIndex: 1, expectedValue: "01"),
            .init(id: "missing", observationIndex: 8, time: 0, portIndex: 1, expectedValue: "1"),
            .init(id: "port", observationIndex: 1, time: 0, portIndex: 9, expectedValue: "1"),
            .init(id: "time", observationIndex: 1, time: 1, portIndex: 1, expectedValue: "1")])
        let engine = NativeLogicSimulationEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let result = try await engine.execute(request)
        #expect(result.status == .completed && result.assessment.status == .failed)
        #expect(result.assessment.violations.map(\.reason) == [.valueMismatch, .valueMismatch, .valueMismatch, .missingObservation, .missingOutput, .timeMismatch])
        #expect(result.assessment.violations.first?.actualValue == "x")
        #expect(throws: LogicSimulationAssessment.Failure.self) { try result.assessment.requirePassed() }
        #expect(try await engine.load(result.acceptance, expectedRequest: request, limits: request.limits).assessment == result.assessment)
    }
    @Test func malformedOrStaleSpecificationCannotPublishAcceptance() async throws {
        let root = try ActualCellRuntimeTests().temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let plain = try request(root: root)
        let engine = NativeLogicSimulationEngine(artifactStore: FileSystemLogicArtifactStore(rootDirectory: root))
        let cases: [[LogicSimulationSpecification.Assertion]] = [[],
            [.init(id: "bad", observationIndex: 0, time: 0, portIndex: 1, expectedValue: "?")],
            [.init(id: "duplicate", observationIndex: 0, time: 0, portIndex: 1, expectedValue: "x"),
             .init(id: "duplicate", observationIndex: 0, time: 0, portIndex: 1, expectedValue: "x")]]
        for assertions in cases {
            let invalid = try specified(plain, root: root, assertions: assertions)
            await #expect(throws: LogicKernelError.self) { try await engine.execute(invalid) }
        }
        let valid = try specified(plain, root: root, assertions: [.init(id: "initial", observationIndex: 0, time: 0, portIndex: 3, expectedValue: "x")])
        let stale = LogicSimulationRequest(runID: "stale", sources: valid.sources, roots: valid.roots, top: valid.top,
            specification: valid.specification, events: [], limits: valid.limits)
        await #expect(throws: LogicKernelError.self) { try await engine.execute(stale) }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/stale/simulation-acceptance-v2.json").path))
        let url = try #require(valid.specification).localFileURL(relativeTo: root, outputRoot: nil)
        try Data("corrupt".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await engine.execute(valid) }
    }
    @Test func changedCurrentRequestAndRehashedForgedArtifactsFailCheckedReload() async throws {
        let root = try ActualCellRuntimeTests().temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try specified(request(root: root), root: root, assertions: [.init(id: "initial", observationIndex: 0, time: 0, portIndex: 3, expectedValue: "x")])
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let engine = NativeLogicSimulationEngine(artifactStore: store)
        let result = try await engine.execute(request)
        let changed = LogicSimulationRequest(runID: request.runID, sources: request.sources, roots: request.roots, top: request.top,
            specification: request.specification, events: [], limits: request.limits)
        await #expect(throws: LogicKernelError.self) { try await engine.load(result.acceptance, expectedRequest: changed, limits: request.limits) }
        let receiptData = try store.read(result.acceptance)
        for mutateObservation in [true, false] {
            var receipt = try #require(JSONSerialization.jsonObject(with: receiptData) as? [String: Any])
            if mutateObservation {
                let saved = try JSONDecoder().decode(LogicSimulationAcceptance.self, from: receiptData)
                var observations = try #require(JSONSerialization.jsonObject(with: store.read(saved.observations)) as? [[String: Any]])
                var outputs = try #require(observations[0]["outputs"] as? [[String: Any]])
                outputs[0]["value"] = "1"; observations[0]["outputs"] = outputs
                let forged = try store.write(JSONSerialization.data(withJSONObject: observations), fileName: "forged-observations.json",
                    outputDirectory: nil, runID: "forged", kind: .waveform, format: .json)
                receipt["observations"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(forged))
            } else {
                var assessment = try #require(receipt["assessment"] as? [String: Any])
                assessment["checkedAssertionCount"] = 9; receipt["assessment"] = assessment
            }
            let forged = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "forged-acceptance-\(mutateObservation).json",
                outputDirectory: nil, runID: "forged", kind: .report, format: .json)
            await #expect(throws: LogicKernelError.self) { try await engine.load(forged, expectedRequest: request, limits: request.limits) }
        }
        let sourceURL = try request.sources[0].artifact.localFileURL(relativeTo: root, outputRoot: nil)
        try Data("changed source".utf8).write(to: sourceURL)
        await #expect(throws: (any Error).self) { try await engine.load(result.acceptance, expectedRequest: request, limits: request.limits) }
    }
    @Test func mappedAcceptanceReplaysActualFunctionsAndHonorsStrictCallerLimits() async throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let synthesis = try await NativeLogicSynthesisEngine(artifactStore: store).execute(helper.request(root: root))
        let plain = LogicSimulationRequest(runID: "mapped-acceptance", mappedReceipt: synthesis.receipt,
            events: [.init(time: 1, updates: [.init(portIndex: 0, value: "10101010"), .init(portIndex: 1, value: "11001100")])], limits: helper.limits())
        let request = try specified(plain, root: root, assertions: [
            .init(id: "and", observationIndex: 1, time: 1, portIndex: 2, expectedValue: "10001000")])
        let engine = NativeLogicSimulationEngine(artifactStore: store)
        let result = try await engine.execute(request)
        try result.assessment.requirePassed()
        let loaded = try await engine.load(result.acceptance, expectedRequest: request, limits: request.limits)
        try loaded.assessment.requirePassed()
        for limits in [helper.limits(tokens: 1), helper.limits(input: 1), helper.limits(timeout: 1)] {
            await #expect(throws: (any Error).self) { try await engine.load(result.acceptance, expectedRequest: request, limits: limits) }
        }
        let unassessed = try await engine.execute(.init(runID: "mapped-unassessed", mappedReceipt: synthesis.receipt,
            events: plain.events, limits: plain.limits))
        #expect(unassessed.assessment.status == .unassessed)
        #expect(throws: LogicSimulationAssessment.Failure.unassessed) { try unassessed.assessment.requirePassed() }
        let task = Task { try await engine.load(result.acceptance, expectedRequest: request, limits: request.limits) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
    @Test func realCLIConsumesPassedFailedUnassessedAndStaleAcceptance() throws {
        let root = try ActualCellRuntimeTests().temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let cli = ActualCellCLITests()
        for expected: String? in ["x", "0", nil] {
            let plain = try request(root: root, runID: "cli-\(expected ?? "none")")
            let request = try expected.map { try specified(plain, root: root, assertions: [
                .init(id: "initial", observationIndex: 0, time: 0, portIndex: 3, expectedValue: $0)]) } ?? plain
            try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
            let execution = try cli.run(["simulate", "--request", "request.json"], root: root)
            #expect(execution.0 == (expected == "0" ? 2 : 0), "\(String(decoding: execution.1, as: UTF8.self))")
            let result = try JSONDecoder().decode(LogicSimulationResult.self, from: execution.1)
            #expect(result.assessment.status == (expected == nil ? .unassessed : expected == "x" ? .passed : .failed))
            let verification = LogicSimulationVerificationRequest(acceptance: result.acceptance, expectedRequest: request, limits: request.limits)
            try JSONEncoder().encode(verification).write(to: root.appending(path: "verify.json"))
            let verified = try cli.run(["verify-simulation", "--request", "verify.json"], root: root)
            #expect(verified.0 == (expected == "x" ? 0 : 2), "\(String(decoding: verified.1, as: UTF8.self))")
            let stale = LogicSimulationRequest(runID: request.runID, sources: request.sources, roots: request.roots,
                top: request.top, specification: request.specification, events: [], limits: request.limits)
            try JSONEncoder().encode(LogicSimulationVerificationRequest(acceptance: result.acceptance, expectedRequest: stale, limits: request.limits))
                .write(to: root.appending(path: "verify.json"))
            #expect(try cli.run(["verify-simulation", "--request", "verify.json"], root: root).0 != 0)
        }
    }
}
