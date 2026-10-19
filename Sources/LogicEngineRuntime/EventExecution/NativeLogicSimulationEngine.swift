import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicKernelCore
import LogicSimulation
import SystemVerilogFrontend

public actor NativeLogicSimulationEngine: LogicSimulationExecuting, LogicSimulationArtifactLoading {
    internal let artifactStore: any LogicArtifactStoring
    private let compiler: any LogicSimulationCompiling
    private let evaluator: any LogicSimulationEvaluating
    public init(artifactStore: any LogicArtifactStoring,
                compiler: any LogicSimulationCompiling = NativeLogicSimulationCompiler(),
                evaluator: any LogicSimulationEvaluating = NativeLogicSimulationEvaluator()) {
        self.artifactStore = artifactStore; self.compiler = compiler; self.evaluator = evaluator
    }
    public func execute(_ request: LogicSimulationRequest) async throws -> LogicSimulationResult {
        try request.validate()
        let started = Date(); let control = LogicRuntimeControl(timeout: request.limits.timeoutNanoseconds)
        var io = LogicRuntimeIO(store: artifactStore, limits: request.limits, control: control)
        var context = LogicKernelContext(limits: try request.limits.kernelLimits(), control: control)
        io.verifiedReadBindings = []
        let specification = try Self.specification(request, io: &io, context: &context)
        let observations = try await evaluate(request, io: &io, context: &context)
        let assessment = try Self.assess(observations, specification: specification, context: &context)
        let operational = try Self.operationalInputs(request, io: io)
        let requestArtifact = try io.write(LogicRuntimeIO.encode(request), name: "simulation-request-v4.json", kind: .request,
            format: .json, runID: request.runID, directory: request.artifactDirectory)
        let observationArtifact = try io.write(LogicRuntimeIO.encode(observations), name: "observations-v4.json", kind: .waveform,
            format: .json, runID: request.runID, directory: request.artifactDirectory)
        let producer = try ProducerIdentity(kind: .engine, identifier: "logic.four-state.simulation", version: "1.2.0",
            build: SHA256ContentDigester().digest(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0])), using: .sha256).hexadecimalValue)
        let provenance = try ExecutionProvenance(producer: producer, inputs: operational.inputs,
            invocation: .inProcess(entryPoint: "LogicEngineRuntime.NativeLogicSimulationEngine.execute"),
            environment: .init(platform: "macOS", architecture: "host", toolchain: "swift-6.4.0-RELEASE"), startedAt: started, completedAt: Date())
        let acceptance = LogicSimulationAcceptance(producer: producer, request: requestArtifact,
            observations: observationArtifact, specification: request.specification, operationalInputs: operational.inputs,
            operationalInputBindings: operational.bindings, assessment: assessment)
        let acceptanceArtifact = try io.write(LogicRuntimeIO.encode(acceptance), name: "simulation-acceptance-v2.json",
            kind: .report, format: .json, runID: request.runID, directory: request.artifactDirectory)
        return try .init(runID: request.runID, observations: observations,
            artifacts: [requestArtifact, observationArtifact, acceptanceArtifact], acceptance: acceptanceArtifact,
            assessment: assessment, provenance: provenance)
    }

    internal func evaluate(_ request: LogicSimulationRequest, io: inout LogicRuntimeIO,
                           context: inout LogicKernelContext) async throws -> [LogicSimulationObservationRecord] {
        let model: LogicSimulationModel
        if let receipt = request.mappedReceipt {
            let verified = try await NativeLogicSynthesisEngine.load(receipt, io: &io, context: &context)
            model = try compiler.compile(verified.mapped, library: verified.mapped.library, context: &context)
        } else {
            let sources = try LogicRuntimeComposition.sources(request.sources, io: &io, context: &context)
            let rtl = try NativeSystemVerilogElaborator().elaborate(sources,
                options: LogicRuntimeComposition.options(roots: request.roots, top: request.top, limits: request.limits, boundedBy: io.limits), context: &context)
            model = try compiler.compile(rtl, context: &context)
        }
        var state = try evaluator.makeState(model, context: &context)
        var observations: [LogicSimulationObservationRecord] = []
        observations.append(try Self.record(evaluator.evaluate(model, event: .init(time: 0, updates: []), state: &state, context: &context), context: &context))
        var lastTime: UInt64 = 0
        for event in request.events {
            guard event.time >= lastTime else { throw LogicKernelError.invalidInput("Simulation event times must be nondecreasing") }
            lastTime = event.time
            var updates: [LogicInputEvent.Update] = []
            for update in event.updates {
                updates.append(.init(portIndex: update.portIndex, value: try Self.value(update.value, context: &context)))
            }
            let observation = try evaluator.evaluate(model, event: .init(time: event.time, updates: updates), state: &state, context: &context)
            observations.append(try Self.record(observation, context: &context))
        }
        return observations
    }

    private static func value(_ text: String, context: inout LogicKernelContext) throws -> LogicFourStateVector {
        let width = try LogicBitWidth(text.utf8.count)
        try context.observeBitWidth(UInt64(width.value))
        _ = try context.reserveStorage(byteCount: UInt64(width.wordCount) * 16)
        var values = [UInt64](repeating: 0, count: width.wordCount)
        var unknowns = values
        for (position, byte) in text.utf8.reversed().enumerated() {
            try context.charge(.workUnits)
            let raw: UInt8
            switch byte { case 48: raw = 0; case 49: raw = 1; case 88,120: raw = 2; case 90,122: raw = 3
            default: throw LogicKernelError.invalidInput("Simulation values contain only 0, 1, x and z") }
            if raw & 1 != 0 { values[position / 64] |= 1 << (position % 64) }
            if raw & 2 != 0 { unknowns[position / 64] |= 1 << (position % 64) }
        }
        return try .init(width: width, valueWords: values, unknownWords: unknowns)
    }
    private static func record(_ observation: LogicObservation, context: inout LogicKernelContext) throws -> LogicSimulationObservationRecord {
        var outputs: [LogicSimulationObservationRecord.Output] = []
        for index in 0..<observation.outputCount {
            let output = try observation.output(at: index); var text = ""
            try context.charge(.outputBytes, amount: UInt64(output.value.width.value))
            for bit in (0..<output.value.width.value).reversed() {
                try context.charge(.workUnits)
                switch try output.value.bit(at: bit) {
                case .zero: text.append("0"); case .one: text.append("1")
                case .unknown: text.append("x"); case .highImpedance: text.append("z")
                }
            }
            outputs.append(.init(portID: output.portID, portIndex: output.portIndex, value: text))
        }
        return .init(time: observation.time, outputs: outputs)
    }
}
