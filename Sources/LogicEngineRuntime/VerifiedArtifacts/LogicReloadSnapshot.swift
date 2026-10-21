import Foundation
import LogicEngineCore
import LogicKernelCore
import TimingCore
import CircuiteFoundation

/// Exact, already-controlled bytes; this type alone grants no circuit/proof authority.
internal final class LogicReloadSnapshot: Sendable {
    struct Entry: Sendable {
        let binding: LogicArtifactBinding
        let data: Data
        let retention: LogicArtifactReadRetention
    }
    let entries: [Entry]
    private let metadata: LogicKernelRetention

    init(entries: consuming [Entry], metadata: LogicKernelRetention) {
        self.entries = entries; self.metadata = metadata
    }

    func read(_ binding: LogicArtifactBinding, context: inout LogicKernelContext) throws -> Data {
        for entry in entries {
            if try LogicReloadComparison.binding(entry.binding, binding, context: &context) { return entry.data }
        }
        throw LogicKernelError.unsupported("Controlled reload dependency was not captured")
    }
    func read(_ binding: LogicArtifactBinding, resources: any LibertySourceResourceAccounting) throws -> Data {
        func string(_ value: String) throws {
            try resources.check(); try resources.chargeWork(UInt64(value.utf8.count)); try resources.check()
        }
        func fields(_ value: LogicArtifactBinding) throws {
            try resources.check(); try resources.chargeWork(152)
            try string(value.digest.hexadecimalValue)
            try string(value.descriptor.role.rawValue); try string(value.descriptor.kind.rawValue)
            try string(value.descriptor.format.rawValue)
            switch value.availability {
            case .local(_, let root, let path):
                try string(root.rawValue)
                for segment in path.segments { try string(segment) }
            case .service(_, let resource):
                try string(resource.serviceID.rawValue); try string(resource.namespaceID.rawValue)
                try string(resource.resourceID.rawValue)
            }
        }
        for entry in entries {
            try fields(entry.binding); try fields(binding)
            if entry.binding == binding { return entry.data }
        }
        throw LogicKernelError.unsupported("Controlled reload dependency was not captured")
    }

}
