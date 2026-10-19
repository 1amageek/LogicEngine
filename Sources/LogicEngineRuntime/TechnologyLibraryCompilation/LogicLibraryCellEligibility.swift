import CircuiteFoundation
import LogicIR
import LogicKernelCore
import TimingCore

public struct LogicLibraryCellEligibility: Sendable {
    public enum Reason: Error, Sendable, Equatable {
        case dontUse
        case invalidCellName
        case missingArea
        case invalidArea
        case noOutput
        case unsupportedDirection(String)
        case missingOutputFunction(String)
        case unexpectedInputFunction(String)
        case unsupportedPinExtension(String)
        case unsupportedFunction(LibertyBooleanFunctionIssue)
        case unsupportedFunctionalGroup(String)
        case unsupportedStateDefinition
        case unsupportedPowerDown
        case requiresOperatingConditions
        case unsupportedControl
        case unknownSymbol(String)
        case outputPinReference(String)
        case duplicatePin(String)
        case ambiguousStateSymbol(String)
        internal var retainedTextByteCount: UInt64 {
            switch self {
            case .unsupportedDirection(let text), .missingOutputFunction(let text),
                 .unexpectedInputFunction(let text), .unsupportedPinExtension(let text),
                 .unsupportedFunctionalGroup(let text), .unknownSymbol(let text),
                 .outputPinReference(let text), .duplicatePin(let text), .ambiguousStateSymbol(let text):
                return UInt64(text.utf8.count)
            default: return 0
            }
        }
    }
    public enum Outcome: Sendable, Equatable {
        case eligible(LogicCellIndex)
        case ineligible(Reason)
    }
    public let cellID: DesignEntityID
    public let name: String
    public let origin: LogicKernelSourceRange
    public let outcome: Outcome
    internal init(cellID: DesignEntityID, name: String, origin: LogicKernelSourceRange, outcome: Outcome) {
        self.cellID = cellID; self.name = name; self.origin = origin; self.outcome = outcome
    }
}
