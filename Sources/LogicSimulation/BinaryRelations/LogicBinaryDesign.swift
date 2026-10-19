import LogicIR

public enum LogicBinaryDesign: Sendable {
    case bit(BitLogicDesign)
    case mapped(MappedGateDesign)
    public var stateCount: Int {
        switch self { case .bit(let design): design.stateCount; case .mapped(let design): design.stateCount }
    }
}
