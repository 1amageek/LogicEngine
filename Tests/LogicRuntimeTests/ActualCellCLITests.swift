import CircuiteFoundation
import Foundation
import Darwin
import LogicEngineCore
import LogicEngineRuntime
import Testing
import STAEngine

@Suite(.timeLimit(.minutes(1)))
struct ActualCellCLITests {
    func run(_ arguments: [String], root: URL, requestLimit: String? = "65536") throws -> (Int32, Data) {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let binary = ProcessInfo.processInfo.environment["LOGIC_ENGINE_CLI"].map { URL(fileURLWithPath: $0) }
            ?? package.appending(path: ".build/arm64-apple-macosx/debug/logic-engine")
        let process = Process(); process.executableURL = binary; process.arguments = arguments + (requestLimit.map { ["--maximum-request-bytes", $0] } ?? [])
        process.currentDirectoryURL = root
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
    @Test func cliSourceToNetlistSaveAndProofReloadWithNonzeroCorruptionFailure() throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try helper.request(root: root)
        try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
        let synthesis = try run(["synthesize", "--request", "request.json", "--root", root.path], root: root)
        #expect(synthesis.0 == 0, "\(String(decoding: synthesis.1, as: UTF8.self))")
        let result = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisResult.self, from: synthesis.1)
        #expect(result.payload.instanceCount == 8 && result.payload.proofKind == "combinational-rup")
        let equivalence = LogicEquivalenceRequest(runID: "cli-reload", receipt: result.receipt, limits: helper.limits())
        try JSONEncoder().encode(equivalence).write(to: root.appending(path: "reload.json"))
        let reloaded = try run(["verify-mapped", "--request", "reload.json", "--root", root.path], root: root)
        #expect(reloaded.0 == 0, "\(String(decoding: reloaded.1, as: UTF8.self))")
        #expect(try JSONDecoder().decode(LogicEquivalenceResult.self, from: reloaded.1).equivalent)
        let simulation = LogicEngineRuntime.LogicSimulationRequest(runID: "cli-events", mappedReceipt: result.receipt,
            events: [.init(time: 1, updates: [.init(portIndex: 0, value: "10101010"), .init(portIndex: 1, value: "11001100")])], limits: helper.limits())
        try JSONEncoder().encode(simulation).write(to: root.appending(path: "simulation.json"))
        let simulated = try run(["simulate", "--request", "simulation.json", "--root", root.path], root: root)
        #expect(simulated.0 == 0, "\(String(decoding: simulated.1, as: UTF8.self))")
        #expect(try JSONDecoder().decode(LogicEngineRuntime.LogicSimulationResult.self, from: simulated.1).observations.last?.outputs.first?.value == "10001000")
        let proofURL = try result.payload.proof.localFileURL(relativeTo: root, outputRoot: nil)
        try Data("corrupt".utf8).write(to: proofURL)
        let corrupt = try run(["verify-mapped", "--request", "reload.json", "--root", root.path], root: root)
        #expect(corrupt.0 != 0)
        let diagnostic = try #require(JSONSerialization.jsonObject(with: corrupt.1) as? [String: Any])
        #expect(diagnostic["status"] as? String == "failed")
    }

    @Test func cliSTAProofPublicationReloadAndRehashedMetricRefusal() throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try ActualCellTimingTests().request(root: root)
        try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
        let synthesis = try run(["synthesize", "--request", "request.json"], root: root)
        #expect(synthesis.0 == 0, "\(String(decoding: synthesis.1, as: UTF8.self))")
        let result = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisResult.self, from: synthesis.1)
        let store = FileSystemLogicArtifactStore(rootDirectory: root)
        let timing = try #require(result.payload.timingResult)
        let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(timing))
        #expect(abs(try #require(sta.payload.worstSetupSlack) - 6e-9) < 1e-20)
        #expect(sta.payload.characterization.contains { $0.conditionName == "typical" && $0.selected })
        let equivalence = LogicEquivalenceRequest(runID: "cli-sta-reload", receipt: result.receipt, limits: helper.limits())
        try JSONEncoder().encode(equivalence).write(to: root.appending(path: "reload.json"))
        let reloaded = try run(["verify-mapped", "--request", "reload.json"], root: root)
        #expect(reloaded.0 == 0, "\(String(decoding: reloaded.1, as: UTF8.self))")
        #expect(try JSONDecoder().decode(LogicEquivalenceResult.self, from: reloaded.1).equivalent)

        var forgedSTA = try #require(JSONSerialization.jsonObject(with: store.read(timing)) as? [String: Any])
        var payload = try #require(forgedSTA["payload"] as? [String: Any])
        payload["worstSetupSlack"] = 9e-9; forgedSTA["payload"] = payload
        let forgedTiming = try store.write(JSONSerialization.data(withJSONObject: forgedSTA), fileName: "forged-sta.json",
            outputDirectory: nil, runID: "forged", kind: .report, format: .json)
        var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
        receipt["timingResult"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(forgedTiming))
        let forgedReceipt = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "forged-receipt.json",
            outputDirectory: nil, runID: "forged", kind: .report, format: .json)
        let forgedRequest = LogicEquivalenceRequest(runID: "cli-forged", receipt: forgedReceipt, limits: helper.limits())
        try JSONEncoder().encode(forgedRequest).write(to: root.appending(path: "forged.json"))
        #expect(try run(["verify-mapped", "--request", "forged.json"], root: root).0 != 0)

        let failure = try ActualCellTimingTests().request(root: root, requiredSlack: 7e-9, runID: "cli-slack-failure")
        try JSONEncoder().encode(failure).write(to: root.appending(path: "failure.json"))
        #expect(try run(["synthesize", "--request", "failure.json"], root: root).0 != 0)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/cli-slack-failure/synthesis-receipt-v4.json").path))
    }
    @Test func cliRequestAdmissionRejectsMissingInvalidSmallCapsAndFIFO() throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        try JSONEncoder().encode(helper.request(root: root)).write(to: root.appending(path: "request.json"))
        for limit: String? in [nil, "0", "-1", "18446744073709551615", "1"] {
            for command in ["synthesize", "verify-mapped", "simulate"] {
                let result = try run([command, "--request", "request.json"], root: root, requestLimit: limit)
                #expect(result.0 != 0)
                let diagnostic = try #require(JSONSerialization.jsonObject(with: result.1) as? [String: Any])
                #expect(diagnostic["status"] as? String == "failed")
            }
        }
        #expect(Darwin.mkfifo(root.appending(path: "fifo.json").path, S_IRUSR | S_IWUSR) == 0)
        #expect(try run(["synthesize", "--request", "fifo.json"], root: root).0 != 0)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine").path))
    }

    @Test func cliAliasesConstantsAndSequentialTieExecuteProofSTAAndReload() throws {
        let helper = ActualCellRuntimeTests()
        for expression in ["a", "1'b0", "1'b1", "ff", "ff-initial"] {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try ActualCellTimingTests().request(root: root, expression: expression,
                sourceText: expression == "ff" ? "module top(input clk,output logic q);always_ff @(posedge clk) q<=1'b0;endmodule"
                    : expression == "ff-initial" ? "module top(input clk,output bit q=1'b1);always_ff @(posedge clk) q<=1'b0;endmodule" : nil,
                libraryFile: expression.hasPrefix("ff") ? "ff-timing.lib" : "timing.lib")
            try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
            let execution = try run(["synthesize", "--request", "request.json"], root: root)
            if expression == "ff-initial" {
                #expect(execution.0 != 0)
                #expect(String(decoding: execution.1, as: UTF8.self).contains("startup realization"))
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/native-sta/synthesis-receipt-v4.json").path))
                continue
            }
            #expect(execution.0 == 0, "\(String(decoding: execution.1, as: UTF8.self))")
            let result = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisResult.self, from: execution.1)
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let timing = try #require(result.payload.timingResult)
            let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(timing))
            if expression == "a" || expression.hasPrefix("ff") {
                #expect(abs(try #require(sta.payload.worstSetupSlack) - (expression == "a" ? 7e-9 : 7.5e-9)) < 1e-20)
            } else {
                #expect(sta.payload.worstSetupSlack == nil && sta.payload.criticalPaths.isEmpty)
                #expect(sta.payload.endpoints[0].staticValue == (expression == "1'b0" ? .zero : .one))
            }
            let replay = LogicEquivalenceRequest(runID: "cli-alias-replay", receipt: result.receipt, limits: request.limits)
            try JSONEncoder().encode(replay).write(to: root.appending(path: "reload.json"))
            #expect(try run(["verify-mapped", "--request", "reload.json"], root: root).0 == 0)
            if expression.hasPrefix("ff") {
                let simulation = LogicEngineRuntime.LogicSimulationRequest(runID: "cli-constant-d", mappedReceipt: result.receipt,
                    events: [.init(time: 1, updates: [.init(portIndex: 0, value: "0")]),
                             .init(time: 2, updates: [.init(portIndex: 0, value: "1")])], limits: request.limits)
                try JSONEncoder().encode(simulation).write(to: root.appending(path: "events.json"))
                let observed = try run(["simulate", "--request", "events.json"], root: root)
                #expect(observed.0 == 0, "\(String(decoding: observed.1, as: UTF8.self))")
                let values = try JSONDecoder().decode(LogicEngineRuntime.LogicSimulationResult.self, from: observed.1)
                    .observations.map { $0.outputs.first?.value }
                #expect(values == (expression == "ff" ? ["x", "x", "0"] : ["1", "1", "0"]))
            }
            if expression == "1'b0" {
                var forged = try #require(JSONSerialization.jsonObject(with: store.read(timing)) as? [String: Any])
                var payload = try #require(forged["payload"] as? [String: Any])
                var endpoints = try #require(payload["endpoints"] as? [[String: Any]])
                endpoints[0]["staticValue"] = "one"; payload["endpoints"] = endpoints; forged["payload"] = payload
                let reboundTiming = try store.write(JSONSerialization.data(withJSONObject: forged), fileName: "wrong-static.json",
                    outputDirectory: nil, runID: "forged", kind: .report, format: .json)
                var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
                receipt["timingResult"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reboundTiming))
                let rebound = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "wrong-receipt.json",
                    outputDirectory: nil, runID: "forged", kind: .report, format: .json)
                try JSONEncoder().encode(LogicEquivalenceRequest(runID: "forged-static", receipt: rebound, limits: request.limits))
                    .write(to: root.appending(path: "forged.json"))
                #expect(try run(["verify-mapped", "--request", "forged.json"], root: root).0 != 0)
            }
        }
    }
    @Test func cliAliasConstraintsCoverageRefusalAndRehashedEndpointReplay() throws {
        let helper = ActualCellRuntimeTests(); let root = try helper.temporary()
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let source = "module top(input a,output y,z);assign y=a;assign z=a;endmodule"
        let sdc = """
        create_clock -name clk -period 10ns [get_ports p0_0]
        set_input_delay 1ns -clock clk [get_ports p0_0]
        set_output_delay 2ns -clock clk [get_ports p1_0]
        """
        for (index, suffix, succeeds) in [(0, "\nset_output_delay 4ns -clock clk [get_ports p2_0]", true),
                                           (1, "", false),
                                           (2, "\nset_output_delay 4ns -clock clk [get_ports p2_0]\nset_max_delay -probe 0.5ns -from [get_ports p0_0] -to [get_ports p2_0]", false)] {
            let request = try ActualCellTimingTests().request(root: root, runID: "cli-alias-\(index)", sourceText: source, sdcText: sdc + suffix)
            try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
            let execution = try run(["synthesize", "--request", "request.json"], root: root)
            if !succeeds {
                #expect(execution.0 != 0)
                #expect(String(decoding: execution.1, as: UTF8.self).contains(index == 1 ? "unconstrained endpoints" : "-probe"))
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/cli-alias-\(index)/synthesis-receipt-v4.json").path))
                continue
            }
            #expect(execution.0 == 0, "\(String(decoding: execution.1, as: UTF8.self))")
            let result = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisResult.self, from: execution.1)
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let timing = try #require(result.payload.timingResult)
            let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(timing))
            #expect(abs(try #require(sta.payload.endpoints.first { $0.endpoint == "p1_0" }?.setupSlack) - 7e-9) < 1e-20)
            #expect(abs(try #require(sta.payload.endpoints.first { $0.endpoint == "p2_0" }?.setupSlack) - 5e-9) < 1e-20)
            try JSONEncoder().encode(LogicEquivalenceRequest(runID: "cli-alias-reload", receipt: result.receipt, limits: request.limits))
                .write(to: root.appending(path: "reload.json"))
            #expect(try run(["verify-mapped", "--request", "reload.json"], root: root).0 == 0)
            var forged = try #require(JSONSerialization.jsonObject(with: store.read(timing)) as? [String: Any])
            var payload = try #require(forged["payload"] as? [String: Any])
            var endpoints = try #require(payload["endpoints"] as? [[String: Any]])
            let alias = try #require(endpoints.firstIndex { $0["endpoint"] as? String == "p1_0" })
            endpoints[alias]["setupSlack"] = 8e-9; payload["endpoints"] = endpoints; forged["payload"] = payload
            let reboundTiming = try store.write(JSONSerialization.data(withJSONObject: forged), fileName: "wrong-alias.json",
                outputDirectory: nil, runID: "forged-alias", kind: .report, format: .json)
            var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
            receipt["timingResult"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reboundTiming))
            let rebound = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "wrong-receipt.json",
                outputDirectory: nil, runID: "forged-alias", kind: .report, format: .json)
            try JSONEncoder().encode(LogicEquivalenceRequest(runID: "forged-alias", receipt: rebound, limits: request.limits))
                .write(to: root.appending(path: "forged.json"))
            #expect(try run(["verify-mapped", "--request", "forged.json"], root: root).0 != 0)
        }
    }
    @Test func cliPathExceptionsExecuteExactProofSTAAndRejectForgedCoverage() throws {
        let helper = ActualCellRuntimeTests()
        for row in ActualCellPathExceptionTests.cases {
            let root = try helper.temporary()
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try ActualCellPathExceptionTests().request(root: root, clause: row.1, excluded: row.0 == "all-false")
            try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
            let execution = try run(["synthesize", "--request", "request.json"], root: root)
            #expect(execution.0 == 0, "\(String(decoding: execution.1, as: UTF8.self))")
            let result = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisResult.self, from: execution.1)
            #expect(result.payload.instanceCount == 1 && result.payload.proofKind == "combinational-rup")
            let store = FileSystemLogicArtifactStore(rootDirectory: root)
            let timing = try #require(result.payload.timingResult)
            let sta = try JSONDecoder().decode(STAExecutionResult.self, from: store.read(timing))
            try ActualCellPathExceptionTests.check(sta, row: row)
            try JSONEncoder().encode(LogicEquivalenceRequest(runID: "cli-exception-replay", receipt: result.receipt, limits: request.limits))
                .write(to: root.appending(path: "reload.json"))
            let verified = try run(["verify-mapped", "--request", "reload.json"], root: root)
            #expect(verified.0 == 0)
            #expect(try JSONDecoder().decode(LogicEquivalenceResult.self, from: verified.1).equivalent)
            if row.0 == "all-false" {
                var forged = try #require(JSONSerialization.jsonObject(with: store.read(timing)) as? [String: Any])
                var payload = try #require(forged["payload"] as? [String: Any])
                var endpoints = try #require(payload["endpoints"] as? [[String: Any]])
                endpoints[0]["excludedChecks"] = ["setup"]; payload["endpoints"] = endpoints; forged["payload"] = payload
                let reboundTiming = try store.write(JSONSerialization.data(withJSONObject: forged), fileName: "forged-excluded.json",
                    outputDirectory: nil, runID: "forged-excluded", kind: .report, format: .json)
                var receipt = try #require(JSONSerialization.jsonObject(with: store.read(result.receipt)) as? [String: Any])
                receipt["timingResult"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reboundTiming))
                let rebound = try store.write(JSONSerialization.data(withJSONObject: receipt), fileName: "forged-receipt.json",
                    outputDirectory: nil, runID: "forged-excluded", kind: .report, format: .json)
                try JSONEncoder().encode(LogicEquivalenceRequest(runID: "forged-excluded", receipt: rebound, limits: request.limits))
                    .write(to: root.appending(path: "forged.json"))
                #expect(try run(["verify-mapped", "--request", "forged.json"], root: root).0 != 0)
            }
            let failure = try ActualCellPathExceptionTests().request(root: root, clause: "set_min_delay 3ns -to [get_ports p1_0]", runID: "cli-min-failure")
            try JSONEncoder().encode(failure).write(to: root.appending(path: "failure.json"))
            #expect(try run(["synthesize", "--request", "failure.json"], root: root).0 != 0)
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".logic-engine/runs/cli-min-failure/synthesis-receipt-v4.json").path))
        }
    }

}
