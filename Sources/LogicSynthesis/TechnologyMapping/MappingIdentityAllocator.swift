import CircuiteFoundation
import LogicKernelCore

internal struct MappingIdentityAllocator {
    var next: UInt64
    var used: Set<DesignEntityID>
    mutating func allocate(context: inout LogicKernelContext) throws(LogicKernelError) -> DesignEntityID {
        while true {
            try context.charge(.workUnits)
            let id = try MappingArithmetic.id(next)
            guard next < .max else { throw .invalidInput("Mapping identity range exhausted") }
            next += 1
            if used.insert(id).inserted { return id }
        }
    }
}
