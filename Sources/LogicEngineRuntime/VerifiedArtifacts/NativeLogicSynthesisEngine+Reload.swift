import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import LogicDesignSerialization
import LogicEngineCore
import LogicIR
import LogicKernelCore
import LogicProof
import LogicLowering
import LogicSynthesis
import SystemVerilogFrontend
import STAEngine
import TimingCore

extension NativeLogicSynthesisEngine {
    public func load(_ receipt: LogicArtifactBinding, limits: LogicRuntimeLimits) async throws -> LogicVerifiedSynthesis {
        let control = LogicRuntimeControl(timeout: limits.timeoutNanoseconds)
        var io = LogicRuntimeIO(store: artifactStore, limits: limits, control: control)
        var context = LogicKernelContext(limits: try limits.kernelLimits(), control: control)
        return try await Self.load(receipt, io: &io, context: &context)
    }

    internal static func load(_ receipt: LogicArtifactBinding, io: inout LogicRuntimeIO,
                              context: inout LogicKernelContext, isolation: isolated (any Actor)? = #isolation) async throws -> LogicVerifiedSynthesis {
        let payload = try JSONDecoder().decode(LogicSynthesisReceipt.self, from: io.read(receipt))
        let request = try JSONDecoder().decode(LogicSynthesisRequest.self, from: io.read(payload.request))
        return try await reload(payload, expectedRequest: request, io: &io, context: &context)
    }

    internal static func reload(_ payload: LogicSynthesisReceipt, expectedRequest: LogicSynthesisRequest,
                         io: inout LogicRuntimeIO, context: inout LogicKernelContext, isolation: isolated (any Actor)? = #isolation) async throws -> LogicVerifiedSynthesis {
        guard payload.schemaVersion == LogicSynthesisReceipt.currentSchemaVersion,
              payload.algorithm == LogicSynthesisReceipt.algorithmIdentity, payload.seed == 0,
              payload.producer.identifier == "logic.actual-cell.synthesis", payload.producer.version == "1.5.0",
              payload.producer.build != nil else {
            throw LogicKernelError.invalidInput("Unsupported actual-cell receipt or algorithm")
        }
        let request: LogicSynthesisRequest
        if let controlled = io.controlled {
            _ = try io.read(payload.request, context: &context)
            request = controlled.request.value
        } else {
            request = try JSONDecoder().decode(LogicSynthesisRequest.self, from: io.read(payload.request))
            try request.validate()
        }
        guard payload.realizationPolicy == request.realizationPolicy else { throw LogicKernelError.invalidInput("Receipt realization policy differs from its request") }
        if io.controlled == nil {
            guard request == expectedRequest else { throw LogicKernelError.invalidInput("Synthesis configuration binding differs") }
        }
        // The controlled entry passes this exact decoded request owner as expectedRequest;
        // it cannot introduce a separately decoded/caller-selected configuration.
        // Source identities are still required even though proof replay consumes the lowered graph.
        let sources: LogicSourceBundle
        let compilation: LogicLibraryCompilation
        var sourceRetention: LogicKernelRetention?
        if let controlled = io.controlled {
            let source = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
                try LogicRuntimeComposition.sources(request, io: &io, context: &inner)
            }
            sources = source.value; sourceRetention = source.retention
            let library = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
                try LogicRuntimeComposition.compilation(request, io: &io, context: &inner)
            }
            compilation = library.value
            controlled.parts.withLock { $0.compilation = library.retention }
        } else {
            sources = try LogicRuntimeComposition.sources(request, io: &io, context: &context)
            compilation = try LogicRuntimeComposition.compilation(request, io: &io, context: &context)
        }
        defer { withExtendedLifetime(sourceRetention) {} }
        guard let library = compilation.library else { throw LogicRuntimeError.unsupported("No functional library on replay") }
        let original: BitLogicDesign
        let identities: MappedGateDesign
        let mapped: MappedGateDesign
        let operating: LogicCheckedOperatingConditions
        if let controlled = io.controlled {
            let originalData = try io.read(payload.originalBitDesign, context: &context)
            let bit = try BitLogicDesignCodec().decodeControlled(originalData, context: &context)
            original = bit.value
            controlled.parts.withLock { $0.original = bit.retention }
            let identityData = try io.read(payload.mappedIdentities, context: &context)
            let identity = try MappedGateDesignCodec().decodeControlled(identityData, library: library, context: &context)
            identities = identity.value
            controlled.parts.withLock { $0.identities = identity.retention }
            let netlist = try io.read(payload.netlist, context: &context)
            let imported = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
                let value = try MappedGateVerilogCodec().decode(netlist, identities: identities, top: request.top, context: &inner)
                try NativeMappedGateRealizationValidator().validate(value, policy: request.realizationPolicy.mappedPolicy, context: &inner)
                return value
            }
            mapped = imported.value
            controlled.parts.withLock { $0.mapped = imported.retention }
            guard try LogicReloadGraphComparison.mapped(mapped, identities, context: &context) else {
                throw LogicKernelError.invalidInput("Verilog physical connectivity differs from its bound identity sidecar")
            }
            let resolved = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
                let corners = try LogicOperatingConditionExpansion.scopes(request, context: &inner)
                return try LogicOperatingConditionExpansion.qualify(mapped, compilation: compilation,
                    libraryReference: request.library.reference, corners: corners, context: &inner)
            }
            operating = resolved.value
            controlled.parts.withLock { $0.operating = resolved.retention }
            // One equality traversal of the actual saved record is separate work.
            try context.charge(.workUnits, amount: controlled.receiptByteCount)
        } else {
            original = try BitLogicDesignCodec().decode(io.read(payload.originalBitDesign), context: &context)
            identities = try MappedGateDesignCodec().decode(io.read(payload.mappedIdentities), library: library, context: &context)
            mapped = try MappedGateVerilogCodec().decode(io.read(payload.netlist), identities: identities,
                top: request.top, context: &context)
            try NativeMappedGateRealizationValidator().validate(mapped, policy: request.realizationPolicy.mappedPolicy, context: &context)
            guard try MappedGateDesignCodec().encode(mapped) == MappedGateDesignCodec().encode(identities) else {
                throw LogicKernelError.invalidInput("Verilog physical connectivity differs from its bound identity sidecar")
            }
            let corners = try LogicOperatingConditionExpansion.scopes(request, context: &context)
            operating = try LogicOperatingConditionExpansion.qualify(mapped, compilation: compilation,
                libraryReference: request.library.reference, corners: corners, context: &context)
        }
        guard operating.receipt == payload.operatingConditions else {
            throw LogicKernelError.invalidInput("Saved operating premises differ from exact-source candidate expansion")
        }
        var rebuiltRetention: LogicKernelRetention?
        let rebuilt: BitLogicDesign
        if let controlled = io.controlled {
            let phase = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
                let rtl = try NativeSystemVerilogElaborator().elaborate(sources,
                    options: LogicRuntimeComposition.options(request, boundedBy: io.limits), context: &inner)
                let word = try NativeLogicWordLowering().lower(rtl, context: &inner)
                return try NativeLogicBitLowering().lower(word, context: &inner)
            }
            rebuilt = phase.value; rebuiltRetention = phase.retention
            guard try LogicReloadGraphComparison.bit(rebuilt, original, context: &context) else {
                throw LogicKernelError.invalidInput("Persisted original bit graph differs from the exact source elaboration")
            }
        } else {
            let rtl = try NativeSystemVerilogElaborator().elaborate(sources, options: LogicRuntimeComposition.options(request, boundedBy: io.limits), context: &context)
            let word = try NativeLogicWordLowering().lower(rtl, context: &context)
            rebuilt = try NativeLogicBitLowering().lower(word, context: &context)
            guard try BitLogicDesignCodec().encode(rebuilt) == BitLogicDesignCodec().encode(original) else {
                throw LogicKernelError.invalidInput("Persisted original bit graph differs from the exact source elaboration")
            }
        }
        defer { withExtendedLifetime(rebuiltRetention) {} }
        let metrics: LogicMappingStatistics
        var metricsRetention: LogicKernelRetention?
        if let controlled = io.controlled {
            let measured = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
                try NativeLogicTechnologyMapper().measure(mapped, context: &inner)
            }
            metrics = measured.value; metricsRetention = measured.retention
        } else {
            metrics = try NativeLogicTechnologyMapper().measure(mapped, context: &context)
        }
        defer { withExtendedLifetime(metricsRetention) {} }
        let area = metrics.area
        guard area == payload.area, metrics.combinationalDepth == payload.combinationalDepth,
              mapped.instanceCount == payload.instanceCount,
              payload.proofKind == (original.stateCount == 0 ? "combinational-rup" : "state-preserving-induction-rup") else {
            throw LogicKernelError.invalidInput("Persisted metrics or proof kind differ from the actual graph")
        }
        if let maximum = request.constraints.maximumArea, area > maximum { throw LogicRuntimeError.constraint("Reloaded candidate area fails") }
        if request.constraints.maximumPower != nil { throw LogicRuntimeError.unsupported("Power is unknown") }
        let certificate: LogicRUPCertificate
        let problem: LogicEquivalenceProblem
        let checked: CheckedLogicEquivalence
        if let controlled = io.controlled {
            let data = try io.read(payload.proof, context: &context)
            let raw = try LogicRUPCertificateCodec().decodeControlled(data, limits: io.limits,
                context: &context, resources: controlled.resources)
            certificate = raw.value
            controlled.parts.withLock { $0.certificate = raw.retention }
            let proof = try LogicReloadKernelPhase.run(context: &context, resources: controlled.resources) { inner in
                let problem = try LogicRuntimeComposition.problem(original, mapped, context: &inner, controlled: true)
                let checked = try NativeLogicEquivalenceChecker().recheck(problem, certificate: certificate, context: &inner)
                try checked.requireBinding(to: problem)
                return (problem, checked)
            }
            problem = proof.value.0; checked = proof.value.1
            controlled.parts.withLock { $0.proof = proof.retention }
        } else {
            certificate = try LogicRUPCertificateCodec().decode(io.read(payload.proof), context: &context)
            problem = try LogicRuntimeComposition.problem(original, mapped, context: &context)
            checked = try NativeLogicEquivalenceChecker().recheck(problem, certificate: certificate, context: &context)
            try checked.requireBinding(to: problem)
        }
        if let constraints = request.constraints.timing {
            if io.controlled != nil {
                try await Self.controlledTimingReload(payload, request: request, mapped: mapped,
                    operating: operating, io: &io, context: &context)
            } else {
            guard let artifact = payload.timingResult else { throw LogicRuntimeError.unsupported("Missing required STA result") }
            let result = try JSONDecoder().decode(STAExecutionResult.self, from: io.read(artifact))
            let designData = try Self.timingDesign(mapped, top: request.top)
            guard let design = result.inputBindings.first,
                  design.digest == (try SHA256ContentDigester().digest(data: designData, using: .sha256)),
                  design.byteCount == UInt64(designData.count) else {
                throw LogicKernelError.invalidInput("STA design differs from actual physical connectivity")
            }
            let sta = try STARequest(runID: request.runID, design: design, topDesignName: request.top,
                libraries: constraints.libraries, constraints: constraints.constraints,
                requestedModeIDs: constraints.modeIDs, requestedCornerIDs: constraints.cornerIDs,
                pdkManifest: constraints.pdkManifest, processID: constraints.processID, pdkVersion: constraints.pdkVersion,
                maxPaths: constraints.maximumPaths, characterizationPolicy: .requireObservedConditions,
                characterizationBindings: constraints.characterizationBindings,
                operatingSupplyAssumptions: try Self.supplyAssumptions(operating, context: &context))
            var snapshots: [ArtifactID: Data] = [:]
            for input in sta.artifactBindings { snapshots[input.id] = try io.read(Self.logicBinding(input)) }
            try Self.validateTiming(result, request: sta, constraints: constraints)
            let replayed = try await NativeSTAEngine(reader: InMemoryTimingArtifactReader(artifacts: snapshots)).execute(sta)
            try context.checkpoint()
            try Self.validateTiming(replayed, request: sta, constraints: constraints)
            guard replayed.payload == result.payload else {
                throw LogicKernelError.invalidInput("Persisted STA metrics differ from native exact-input replay")
            }
            }
        } else if payload.timingResult != nil { throw LogicKernelError.invalidInput("Unexpected STA result") }
        return .init(request: request, receipt: payload, original: original, mapped: mapped, problem: problem, equivalence: checked,
            operatingConditions: operating, compilation: compilation)
    }
}
