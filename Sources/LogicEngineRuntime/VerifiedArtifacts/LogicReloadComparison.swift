import CircuiteFoundation
import LogicEngineCore
import LogicKernelCore

internal enum LogicReloadComparison {
    static func string(_ lhs: String, _ rhs: String,
                       context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try charge(UInt64(lhs.utf8.count), UInt64(rhs.utf8.count), context: &context)
        return lhs == rhs
    }

    static func binding(_ lhs: LogicArtifactBinding, _ rhs: LogicArtifactBinding,
                        context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try reference(lhs.reference, rhs.reference, context: &context)
        try availability(lhs.availability, context: &context)
        try availability(rhs.availability, context: &context)
        return lhs == rhs
    }

    static func reference(_ lhs: ArtifactReference, _ rhs: ArtifactReference,
                          context: inout LogicKernelContext) throws(LogicKernelError) {
        // Controlled reload accepts only the fixed canonical SHA-256 ID profile.
        try context.charge(.workUnits, amount: 2 * 152)
        _ = try string(lhs.digest.hexadecimalValue, rhs.digest.hexadecimalValue, context: &context)
        _ = try string(lhs.descriptor.role.rawValue, rhs.descriptor.role.rawValue, context: &context)
        _ = try string(lhs.descriptor.kind.rawValue, rhs.descriptor.kind.rawValue, context: &context)
        _ = try string(lhs.descriptor.format.rawValue, rhs.descriptor.format.rawValue, context: &context)
    }

    private static func availability(_ value: ArtifactAvailability,
                                     context: inout LogicKernelContext) throws(LogicKernelError) {
        switch value {
        case .local(_, let root, let path):
            try charge(UInt64(root.rawValue.utf8.count), 1, context: &context)
            for segment in path.segments {
                try charge(UInt64(segment.utf8.count), 1, context: &context)
            }
        case .service(_, let resource):
            try charge(UInt64(resource.serviceID.rawValue.utf8.count), 1, context: &context)
            try charge(UInt64(resource.namespaceID.rawValue.utf8.count), 1, context: &context)
            try charge(UInt64(resource.resourceID.rawValue.utf8.count), 1, context: &context)
        }
    }

    static func charge(_ lhs: UInt64, _ rhs: UInt64,
                       context: inout LogicKernelContext) throws(LogicKernelError) {
        let amount = lhs.addingReportingOverflow(rhs)
        guard !amount.overflow else { throw .invalidInput("Reload comparison work overflows") }
        try context.charge(.workUnits, amount: amount.partialValue)
    }
}
