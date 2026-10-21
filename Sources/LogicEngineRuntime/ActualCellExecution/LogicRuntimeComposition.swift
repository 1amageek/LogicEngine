import CircuiteFoundation
import Foundation
import LogicDesignSerialization
import LogicEngineCore
import LogicIR
import LogicKernelCore
import LogicProof
import LogicSimulation
import SystemVerilogFrontend
import TimingCore

internal enum LogicRuntimeComposition {
    static func compilation(_ request: LogicSynthesisRequest, io: inout LogicRuntimeIO,
                            context: inout LogicKernelContext) throws -> LogicLibraryCompilation {
        if io.controlled != nil {
            return try controlledCompilation(request, io: &io, context: &context)
        }
        let bytes = Array(try io.read(request.library))
        let usage = context.usage
        let limits = context.limits
        let resources = LogicLibertyRuntimeResources(
            maximumStorage: limits[.managedStorageBytes] - usage[.managedStorageBytes],
            maximumWork: limits[.workUnits] - usage[.workUnits],
            maximumAllocations: limits[.allocationBytes] - usage[.allocationBytes], control: io.control)
        let source = try LibertyParser().parseSource(bytes.span,
            limits: .init(maximumNestingDepth: min(request.limits.maximumNesting, io.limits.maximumNesting)), resources: resources)
        let parseUsage = resources.usage
        _ = try context.reserveStorage(byteCount: parseUsage.peak)
        if parseUsage.allocations > parseUsage.peak {
            try context.charge(.allocationBytes, amount: parseUsage.allocations - parseUsage.peak)
        }
        try context.charge(.workUnits, amount: parseUsage.work)
        try LogicOperatingProcessValidation.validate(request, source: source, io: &io, context: &context)
        let compiled = try NativeLogicTechnologyLibraryCompiler().compile(source, identity: request.library.id,
            options: .init(firstEntityID: .init(rawValue: request.limits.firstLibraryEntityID),
                operatingConditionPolicies: request.operatingConditionPolicies,
                sourceStorageCredit: parseUsage.peak - parseUsage.current), context: &context)
        guard compiled.library != nil else { throw LogicRuntimeError.unsupported("No eligible actual-function cells") }
        return compiled
    }

    static func sources(_ request: LogicSynthesisRequest, io: inout LogicRuntimeIO,
                        context: inout LogicKernelContext) throws -> LogicSourceBundle {
        try sources(request.sources, io: &io, context: &context)
    }
    static func sources(_ inputs: [LogicSourceInput], io: inout LogicRuntimeIO,
                        context: inout LogicKernelContext) throws -> LogicSourceBundle {
        if io.controlled != nil {
            return try controlledSources(inputs, io: &io, context: &context)
        }
        var documents: [LogicSourceDocument] = []
        for input in inputs {
            documents.append(try .init(logicalName: input.logicalName, artifactID: input.artifact.id,
                bytes: Array(io.read(input.artifact)), context: &context))
        }
        return try .init(documents: documents, context: &context)
    }
    static func options(_ request: LogicSynthesisRequest, boundedBy caller: LogicRuntimeLimits) throws -> SystemVerilogElaborationOptions {
        let n = min(request.limits.maximumTableEntries, caller.maximumTableEntries)
        let nesting = min(request.limits.maximumNesting, caller.maximumNesting)
        return try .init(roots: request.roots, top: request.top,
            maximumTokens: min(request.limits.maximumTokens, caller.maximumTokens),
            syntax: .init(nodes: n, children: n, symbols: n, nesting: nesting),
            rtl: .init(signals: n, expressions: n, operands: n, statements: n, children: n,
                       caseItems: n, caseMatches: n, ports: n, processes: n), maximumNesting: nesting)
    }
    static func options(roots: [String], top: String, limits: LogicRuntimeLimits,
                        boundedBy caller: LogicRuntimeLimits) throws -> SystemVerilogElaborationOptions {
        let n = min(limits.maximumTableEntries, caller.maximumTableEntries)
        let nesting = min(limits.maximumNesting, caller.maximumNesting)
        return try .init(roots: roots, top: top, maximumTokens: min(limits.maximumTokens, caller.maximumTokens),
            syntax: .init(nodes: n, children: n, symbols: n, nesting: nesting),
            rtl: .init(signals: n, expressions: n, operands: n, statements: n, children: n, caseItems: n,
                       caseMatches: n, ports: n, processes: n), maximumNesting: nesting)
    }
    static func problem(_ original: BitLogicDesign, _ mapped: MappedGateDesign,
                        context: inout LogicKernelContext, controlled: Bool = false) throws -> LogicEquivalenceProblem {
        let counts = try original.withTables { _, _, ports, _, states, _ in
            var inputs = 0; var outputs = 0
            for p in ports.indices {
                if controlled { try context.charge(.workUnits) }
                if ports[p].direction == .input { inputs += ports[p].bits.count } else { outputs += ports[p].bits.count }
            }
            return (inputs, outputs, states.count)
        }
        func pairs(_ count: Int) throws -> [LogicBitCorrespondence] {
            if !controlled { return try (0..<count).map { try .init(reference: $0, candidate: $0) } }
            let size = UInt64(count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicBitCorrespondence>.stride))
            guard !size.overflow else { throw LogicKernelError.invalidInput("Proof correspondence capacity overflows") }
            _ = try context.reserveStorage(byteCount: size.partialValue)
            var result: [LogicBitCorrespondence] = []
            result.reserveCapacity(count)
            for index in 0..<count {
                try context.charge(.workUnits)
                result.append(try .init(reference: index, candidate: index))
            }
            return result
        }
        return try .init(reference: .bit(original), candidate: .mapped(mapped), inputs: pairs(counts.0),
                         outputs: pairs(counts.1), states: pairs(counts.2), context: &context)
    }
}
