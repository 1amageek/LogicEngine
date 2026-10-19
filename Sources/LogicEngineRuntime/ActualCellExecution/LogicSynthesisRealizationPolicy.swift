import LogicIR

/// Host request coding for the canonical mapped realization contract.
public enum LogicSynthesisRealizationPolicy: String, Sendable, Hashable, Codable {
    case standardNetlist
    case physicalCells

    internal var mappedPolicy: MappedGateRealizationPolicy {
        switch self {
        case .standardNetlist: .standardNetlist
        case .physicalCells: .physicalCells
        }
    }
}
