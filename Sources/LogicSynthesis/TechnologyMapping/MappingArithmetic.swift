import CircuiteFoundation
import LogicKernelCore

internal enum MappingArithmetic {
    static func sum(_ a: Int, _ b: Int) throws(LogicKernelError) -> Int {
        let v = a.addingReportingOverflow(b)
        guard !v.overflow, v.partialValue >= 0 else { throw .invalidInput("Mapping capacity overflows") }
        return v.partialValue
    }
    static func product(_ a: Int, _ b: Int) throws(LogicKernelError) -> Int {
        let v = a.multipliedReportingOverflow(by: b)
        guard !v.overflow, v.partialValue >= 0 else { throw .invalidInput("Mapping capacity overflows") }
        return v.partialValue
    }
    static func id(_ raw: UInt64) throws(LogicKernelError) -> DesignEntityID {
        do { return try .init(rawValue: raw) } catch { throw .invalidInput("Mapping identity range exhausted") }
    }
    static func mask(_ count: Int) -> UInt64 { count == 6 ? .max : (UInt64(1) << (1 << count)) - 1 }
    static func variable(_ index: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for row in 0..<(1 << count) where row & (1 << index) != 0 { value |= UInt64(1) << row }
        return value
    }
}
