import Foundation

public enum LogicLoweringError: Error, Sendable, Hashable, LocalizedError {
    case missingTopModule(String)
    case unsupported(entity: String, construct: String)
    case invalidDesign(String)
    case widthMismatch(entity: String, expected: Int, actual: Int)
    case multipleDriver(String)

    public var errorDescription: String? {
        switch self {
        case .missingTopModule(let name):
            return "Top RTL module was not found: \(name)."
        case .unsupported(let entity, let construct):
            return "RTL construct \(construct) is unsupported for \(entity)."
        case .invalidDesign(let message):
            return "RTL lowering input is invalid: \(message)."
        case .widthMismatch(let entity, let expected, let actual):
            return "RTL width mismatch for \(entity): expected \(expected), received \(actual)."
        case .multipleDriver(let signal):
            return "Signal has multiple lowering drivers: \(signal)."
        }
    }
}
