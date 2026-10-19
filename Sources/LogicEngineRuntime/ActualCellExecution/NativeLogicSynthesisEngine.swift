import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import LogicDesignSerialization
import LogicEngineCore
import LogicIR
import LogicKernelCore
import LogicLowering
import LogicProof
import LogicSynthesis
import STAEngine
import SystemVerilogFrontend

public actor NativeLogicSynthesisEngine: LogicSynthesisExecuting, LogicSynthesisArtifactLoading {
    internal let artifactStore: any LogicArtifactStoring
    private let elaborator: any SystemVerilogElaborating
    private let wordLowering: any LogicWordLowering
    private let bitLowering: any LogicBitLowering
    private let optimizer: any LogicOptimizing
    private let mapper: any LogicTechnologyMapping
    private let equivalence: any LogicEquivalenceChecking
    internal let timing: (any STAExecuting)?

    public init(artifactStore: any LogicArtifactStoring,
                elaborator: any SystemVerilogElaborating = NativeSystemVerilogElaborator(),
                wordLowering: any LogicWordLowering = NativeLogicWordLowering(),
                bitLowering: any LogicBitLowering = NativeLogicBitLowering(),
                optimizer: any LogicOptimizing = NativeLogicOptimizer(),
                mapper: any LogicTechnologyMapping = NativeLogicTechnologyMapper(),
                equivalence: any LogicEquivalenceChecking = NativeLogicEquivalenceChecker(),
                timing: (any STAExecuting)? = nil) {
        self.artifactStore = artifactStore; self.elaborator = elaborator; self.wordLowering = wordLowering
        self.bitLowering = bitLowering; self.optimizer = optimizer; self.mapper = mapper
        self.equivalence = equivalence; self.timing = timing
    }

    public func execute(_ request: LogicSynthesisRequest) async throws -> LogicSynthesisResult {
        try request.validate()
        let started = Date(); let control = LogicRuntimeControl(timeout: request.limits.timeoutNanoseconds)
        var context = LogicKernelContext(limits: try request.limits.kernelLimits(), control: control)
        var io = LogicRuntimeIO(store: artifactStore, limits: request.limits, control: control)
        let source: LogicSourceBundle
        let library: LogicTechnologyLibrary
        let compilation: LogicLibraryCompilation
        do {
            source = try LogicRuntimeComposition.sources(request, io: &io, context: &context)
        } catch { throw LogicRuntimeError.input(error) }
        do {
            compilation = try LogicRuntimeComposition.compilation(request, io: &io, context: &context)
            guard let compiled = compilation.library else { throw LogicRuntimeError.unsupported("No functional library") }
            library = compiled
        }
        catch { throw LogicRuntimeError.library(error) }
        let original: BitLogicDesign
        let candidate: LogicMappingCandidate
        do {
            let rtl = try elaborator.elaborate(source, options: LogicRuntimeComposition.options(request, boundedBy: io.limits), context: &context)
            let word = try wordLowering.lower(rtl, context: &context)
            original = try bitLowering.lower(word, context: &context)
            let optimized = try optimizer.optimize(original, context: &context)
            candidate = try mapper.map(optimized.design, library: library,
                policy: .init(maximumCutInputs: request.limits.maximumCutInputs,
                    maximumCellInputs: request.limits.maximumCellInputs, maximumCutsPerNode: request.limits.maximumCutsPerNode,
                    firstEntityID: .init(rawValue: request.limits.firstMappedEntityID),
                    realizationPolicy: request.realizationPolicy.mappedPolicy), context: &context)
        } catch { throw LogicRuntimeError.kernel(error) }
        try NativeMappedGateRealizationValidator().validate(candidate.design, policy: request.realizationPolicy.mappedPolicy, context: &context)
        let netlist: Data; let identities: Data; let imported: MappedGateDesign
        do {
            identities = try MappedGateDesignCodec().encode(candidate.design)
            netlist = try MappedGateVerilogCodec().encode(candidate.design, top: request.top)
            imported = try MappedGateVerilogCodec().decode(netlist, identities: candidate.design, top: request.top, context: &context)
        } catch { throw LogicRuntimeError.codec(error) }
        try NativeMappedGateRealizationValidator().validate(imported, policy: request.realizationPolicy.mappedPolicy, context: &context)
        guard try MappedGateDesignCodec().encode(imported) == identities else {
            throw LogicKernelError.invalidInput("Standard netlist differs from its mapped identity graph")
        }
        let corners = try LogicOperatingConditionExpansion.scopes(request, context: &context)
        let operating = try LogicOperatingConditionExpansion.qualify(imported, compilation: compilation,
            libraryReference: request.library.reference, corners: corners, context: &context)
        let problem = try LogicRuntimeComposition.problem(original, imported, context: &context)
        let checked: CheckedLogicEquivalence
        switch try equivalence.check(problem, context: &context) {
        case .equivalent(let proof): try proof.requireBinding(to: problem); checked = proof
        case .different(let witness): throw LogicRuntimeError.different(witness)
        case .inconclusive(.interrupted(let error)): throw LogicRuntimeError.proof(error)
        case .inconclusive(let reason): throw LogicRuntimeError.inconclusive(reason)
        }
        // Recheck unconditionally so an injected search implementation cannot bypass proof admission.
        _ = try NativeLogicEquivalenceChecker().recheck(problem, certificate: checked.proof.certificate, context: &context)
        if let maximum = request.constraints.maximumArea, candidate.statistics.area > maximum {
            throw LogicRuntimeError.constraint("Actual candidate area exceeds the required maximum")
        }
        if request.constraints.maximumPower != nil { throw LogicRuntimeError.unsupported("Power is unknown without a power/activity model") }
        let timingResult = try await analyzeTiming(request, mapped: imported, operating: operating, io: &io, context: &context)
        try context.checkpoint()
        let producer = try ProducerIdentity(kind: .engine, identifier: "logic.actual-cell.synthesis", version: "1.5.0",
            build: SHA256ContentDigester().digest(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0])), using: .sha256).hexadecimalValue)
        let payload: LogicSynthesisReceipt; let receipt: LogicArtifactBinding
        do {
            let requestArtifact = try io.write(LogicRuntimeIO.encode(request), name: "request-v7.json", kind: .request, format: .json, request: request)
            let bit = try io.write(BitLogicDesignCodec().encode(original), name: "original-bit-v1.json", kind: .netlist, format: .json, request: request)
            let mapped = try io.write(identities, name: "mapped-identities-v1.json", kind: .netlist, format: .json, request: request)
            let structural = try io.write(netlist, name: "mapped.v", kind: .netlist, format: .verilog, request: request)
            let proof = try io.write(LogicRUPCertificateCodec().encode(checked.proof.certificate), name: "equivalence-rup-v1.json", kind: .report, format: .json, request: request)
            payload = .init(producer: producer, realizationPolicy: request.realizationPolicy, request: requestArtifact, originalBitDesign: bit, mappedIdentities: mapped, netlist: structural,
                proof: proof, timingResult: timingResult, operatingConditions: operating.receipt, instanceCount: candidate.statistics.instanceCount,
                area: candidate.statistics.area, combinationalDepth: candidate.statistics.combinationalDepth,
                proofKind: original.stateCount == 0 ? "combinational-rup" : "state-preserving-induction-rup")
            // Validate the persisted files through the same read path before publishing the receipt.
            _ = try await Self.reload(payload, expectedRequest: request, io: &io, context: &context)
            receipt = try io.write(LogicRuntimeIO.encode(payload), name: "synthesis-receipt-v4.json", kind: .report, format: .json, request: request)
        } catch { throw LogicRuntimeError.persistence(error) }
        let provenance = try ExecutionProvenance(producer: producer, inputs: request.inputs,
            invocation: .inProcess(entryPoint: "LogicEngineRuntime.NativeLogicSynthesisEngine.execute"),
            environment: .init(platform: "macOS",
                architecture: "host", toolchain: "swift-6.4.0-RELEASE"), startedAt: started, completedAt: Date())
        return try .init(runID: request.runID, receipt: receipt, payload: payload, provenance: provenance)
    }
}
