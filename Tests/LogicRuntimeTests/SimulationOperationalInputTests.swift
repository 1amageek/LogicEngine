import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicEngineRuntime
import STAEngine
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SimulationOperationalInputTests {
    @Test func timedMappedReplayRetainsExactActualInputClosureThroughAPIAndCLI() async throws {
        let helper = ActualCellRuntimeTests(); let support = SimulationAcceptanceTests()
        let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let synthesisRequest = try ActualCellTimingTests().request(root: root)
        let synthesis = try await NativeLogicSynthesisEngine(artifactStore: store).execute(synthesisRequest)
        let plain = LogicSimulationRequest(runID: "operational-api", mappedReceipt: synthesis.receipt,
            events: [.init(time: 1, updates: [.init(portIndex: 0, value: "1")])], limits: helper.limits())
        let request = try support.specified(plain, root: root, assertions: [
            .init(id: "inv", observationIndex: 1, time: 1, portIndex: 1, expectedValue: "0")])
        let engine = NativeLogicSimulationEngine(artifactStore: store)
        let result = try await engine.execute(request)
        let checked = try await engine.load(result.acceptance, expectedRequest: request, limits: request.limits)
        try checked.assessment.requirePassed()
        let receipt = try JSONDecoder().decode(LogicSynthesisReceipt.self, from: store.read(synthesis.receipt))
        let timing = try #require(receipt.timingResult)
        let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(timing))
        let expected = Set(request.inputs + synthesisRequest.inputs + receipt.artifacts.map(\.reference) + sta.inputBindings.map(\.reference))
        #expect(Set(checked.operationalInputs) == expected)
        #expect(checked.operationalInputs == result.provenance.inputs)
        #expect(checked.operationalInputBindings.map(\.reference) == checked.operationalInputs)
        #expect(checked.producer == result.provenance.producer)
        #expect(checked.operationalInputs.contains(synthesis.payload.netlist.reference))
        #expect(checked.operationalInputs.contains(try #require(synthesisRequest.constraints.timing).pdkManifest.reference))
        #expect(result.artifacts.allSatisfy { !expected.contains($0) })
        for binding in checked.operationalInputBindings { _ = try store.read(binding) }
        let cliRequest = LogicSimulationRequest(runID: "operational-cli", mappedReceipt: request.mappedReceipt,
            specification: request.specification, events: request.events, limits: request.limits)
        try JSONEncoder().encode(cliRequest).write(to: root.appending(path: "simulation.json"))
        let cli = ActualCellCLITests()
        let output = try cli.run(["simulate", "--request", "simulation.json"], root: root)
        #expect(output.0 == 0, "\(String(decoding: output.1, as: UTF8.self))")
        let cliResult = try JSONDecoder().decode(LogicSimulationResult.self, from: output.1)
        #expect(cliResult.provenance.inputs == checked.operationalInputs)
        let verification = LogicSimulationVerificationRequest(acceptance: cliResult.acceptance,
            expectedRequest: cliRequest, limits: request.limits)
        try JSONEncoder().encode(verification).write(to: root.appending(path: "verification.json"))
        let verified = try cli.run(["verify-simulation", "--request", "verification.json"], root: root)
        #expect(verified.0 == 0, "\(String(decoding: verified.1, as: UTF8.self))")
        let cliChecked = try JSONDecoder().decode(LogicSimulationAcceptance.self, from: verified.1)
        #expect(cliChecked.operationalInputs == cliResult.provenance.inputs)
        #expect(cliChecked.operationalInputBindings == checked.operationalInputBindings)
    }

    @Test func rehashedMissingExtraReorderedBindingsAndLegacyClosureFailAPIAndCLI() async throws {
        let helper = ActualCellRuntimeTests(); let support = SimulationAcceptanceTests()
        let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let synthesisRequest = try helper.request(root: root)
        let synthesis = try await NativeLogicSynthesisEngine(artifactStore: store).execute(synthesisRequest)
        let request = try support.specified(.init(runID: "operational-negative", mappedReceipt: synthesis.receipt,
            events: [], limits: helper.limits()), root: root, assertions: [
                .init(id: "initial", observationIndex: 0, time: 0, portIndex: 2, expectedValue: "xxxxxxxx")])
        let engine = NativeLogicSimulationEngine(artifactStore: store)
        let result = try await engine.execute(request)
        let checked = try await engine.load(result.acceptance, expectedRequest: request, limits: request.limits)
        let receipt = try JSONDecoder().decode(LogicSynthesisReceipt.self, from: store.read(synthesis.receipt))
        #expect(Set(checked.operationalInputs) == Set(request.inputs + synthesisRequest.inputs + receipt.artifacts.map(\.reference)))
        let original = try #require(JSONSerialization.jsonObject(with: store.read(result.acceptance)) as? [String: Any])
        let extra = try helper.input(Data("unused source".utf8), name: "unused.json", format: .json, root: root)
        let cli = ActualCellCLITests()
        for mutation in ["missing", "extra", "reordered", "duplicate", "availability", "no-closure", "legacy", "producer"] {
            var object = original
            var inputs = try #require(object["operationalInputs"] as? [[String: Any]])
            switch mutation {
            case "missing":
                inputs.removeAll { value in (value["id"] as? String) == synthesis.payload.netlist.id.description }
                object["operationalInputs"] = inputs
            case "extra":
                inputs.append(try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(extra.reference)) as? [String: Any]))
                object["operationalInputs"] = inputs
            case "reordered": object["operationalInputs"] = inputs.reversed().map { $0 }
            case "duplicate": object["operationalInputs"] = inputs + [try #require(inputs.first)]
            case "availability":
                var bindings = try #require(object["operationalInputBindings"] as? [[String: Any]])
                let forged = try LogicArtifactBinding.local(reference: checked.operationalInputs[0], fileURL: root.appending(path: "unused-location"))
                bindings[0] = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(forged)) as? [String: Any])
                object["operationalInputBindings"] = bindings
            case "no-closure": object.removeValue(forKey: "operationalInputs")
            case "legacy": object["schemaVersion"] = 1; object["algorithm"] = "logic.four-state.acceptance.v1"
            default:
                var producer = try #require(object["producer"] as? [String: Any])
                producer["version"] = "1.1.0"; object["producer"] = producer
            }
            let forged = try store.write(JSONSerialization.data(withJSONObject: object), fileName: "forged-\(mutation).json",
                outputDirectory: nil, runID: "operational-forged", kind: .report, format: .json)
            await #expect(throws: (any Error).self) { try await engine.load(forged, expectedRequest: request, limits: request.limits) }
            try JSONEncoder().encode(LogicSimulationVerificationRequest(acceptance: forged, expectedRequest: request, limits: request.limits))
                .write(to: root.appending(path: "verification.json"))
            #expect(try cli.run(["verify-simulation", "--request", "verification.json"], root: root).0 != 0)
        }
    }
}
