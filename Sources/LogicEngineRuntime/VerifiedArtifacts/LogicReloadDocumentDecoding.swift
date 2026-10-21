import Foundation
import LogicKernelCore
import PDKCore
import PDKDiscovery

internal enum LogicReloadDocumentDecoding {
    static func decode<Value: Decodable & Sendable>(_ type: Value.Type, data: Data,
        limits: LogicRuntimeLimits, context: inout LogicKernelContext, resources: LogicReloadResources,
        validate: (any Decoder) throws -> Void) throws -> PDKDecodedDocument<Value> {
        let phase = try LogicReloadPhase.make(context: &context, resources: resources)
        let result: PDKDecodedDocument<Value>
        do {
            let accounting = try LogicReloadDocumentResources.make(phase: phase, maximumNesting: limits.maximumNesting)
            // The Data owner remains alive for the complete scoped decoder call.
            result = try data.withUnsafeBytes { pointer in
                let bytes = pointer.bindMemory(to: UInt8.self)
                return try NativePDKBoundedDocumentDecoder().decodeAudited(type,
                    bytes: bytes.span, accounting: accounting, rejectUnknownFields: false, validate: validate)
            }
        } catch {
            do { try phase.importOnce(into: &context) }
            catch let secondary { throw LogicControlledReloadFailure(primary: resources.resolved(error), secondary: secondary) }
            throw resources.resolved(error)
        }
        try phase.importOnce(into: &context)
        try resources.checkCaller()
        return result
    }
    static func manifest(data: Data, limits: LogicRuntimeLimits,
        context: inout LogicKernelContext, resources: LogicReloadResources) throws -> PDKControlledManifest {
        let phase = try LogicReloadPhase.make(context: &context, resources: resources)
        let result: PDKControlledManifest
        do {
            let accounting = try LogicReloadDocumentResources.make(phase: phase, maximumNesting: limits.maximumNesting)
            // UInt8 has byte alignment; the immutable Data owner and borrow cover
            // the whole synchronous decoder call. No pointer escapes this closure.
            result = try data.withUnsafeBytes { pointer in
                try NativePDKBoundedDocumentDecoder().decodeAndValidateManifest(
                    bytes: pointer.bindMemory(to: UInt8.self).span, accounting: accounting)
            }
        } catch {
            do { try phase.importOnce(into: &context) }
            catch let secondary { throw LogicControlledReloadFailure(primary: resources.resolved(error), secondary: secondary) }
            throw resources.resolved(error)
        }
        try phase.importOnce(into: &context)
        try resources.checkCaller()
        return result
    }

}
