import Foundation
import LogicEngineCore
import LogicIR
import LogicKernelCore
import TimingCore

extension LogicRuntimeComposition {
    static func controlledCompilation(_ request: LogicSynthesisRequest, io: inout LogicRuntimeIO,
        context: inout LogicKernelContext) throws -> LogicLibraryCompilation {
        guard let controlled = io.controlled else { throw LogicKernelError.invalidInput("Missing controlled reload state") }
        let data = try io.read(request.library, context: &context)
        let conversion = try context.reserveStorage(byteCount: UInt64(data.count))
        let source: OwnedLibertySource
        let phase = try LogicReloadPhase.make(context: &context, resources: controlled.resources)
        let resources: LogicReloadLibertyResources
        do {
            resources = try LogicReloadLibertyResources.make(phase: phase)
            try phase.chargeWork(UInt64(data.count))
            let bytes = Array(data)
            source = try LibertyParser().parseSource(bytes.span,
                limits: .init(maximumNestingDepth: min(request.limits.maximumNesting, io.limits.maximumNesting)),
                resources: resources)
        } catch {
            do {
                try context.releaseStorage(conversion)
                try phase.importOnce(into: &context)
            } catch let cleanup { throw LogicControlledReloadFailure(primary: controlled.resources.resolved(error), secondary: cleanup) }
            throw controlled.resources.resolved(error)
        }
        try context.releaseStorage(conversion)
        try resources.finishParse(into: &context)
        try LogicOperatingProcessValidation.validate(request, source: source, io: &io, context: &context)
        let compiled = try NativeLogicTechnologyLibraryCompiler().compile(source, identity: request.library.id,
            options: .init(firstEntityID: .init(rawValue: request.limits.firstLibraryEntityID),
                operatingConditionPolicies: request.operatingConditionPolicies, sourceStorageCredit: 0), context: &context)
        guard compiled.library != nil else { throw LogicRuntimeError.unsupported("No eligible actual-function cells") }
        return compiled
    }

    static func controlledSources(_ inputs: [LogicSourceInput], io: inout LogicRuntimeIO,
        context: inout LogicKernelContext) throws -> LogicSourceBundle {
        let size = UInt64(inputs.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicSourceDocument>.stride))
        guard !size.overflow else { throw LogicKernelError.invalidInput("Source document capacity overflows") }
        let container = try context.reserveStorage(byteCount: size.partialValue)
        let result: LogicSourceBundle
        do {
            var documents: [LogicSourceDocument] = []
            documents.reserveCapacity(inputs.count)
            for input in inputs {
                let data = try io.read(input.artifact, context: &context)
                let conversion = try context.reserveStorage(byteCount: UInt64(data.count))
                do {
                    try context.charge(.workUnits, amount: UInt64(data.count))
                    let bytes = Array(data)
                    documents.append(try .init(logicalName: input.logicalName,
                        artifactID: input.artifact.id, bytes: bytes, context: &context))
                } catch {
                    do { try context.releaseStorage(conversion) }
                    catch let cleanup { throw LogicControlledReloadFailure(primary: error, secondary: cleanup) }
                    throw error
                }
                try context.releaseStorage(conversion)
            }
            result = try LogicSourceBundle(documents: documents, context: &context)
        } catch {
            do { try context.releaseStorage(container) }
            catch let cleanup { throw LogicControlledReloadFailure(primary: error, secondary: cleanup) }
            throw error
        }
        try context.releaseStorage(container)
        return result
    }
}
