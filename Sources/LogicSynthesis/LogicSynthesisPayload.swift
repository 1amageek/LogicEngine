import Foundation
import XcircuitePackage
import LogicIR
import PowerIntent
import TimingCore
import PDKCore
import LogicEngineCore

public struct LogicSynthesisPayload: Sendable, Hashable, Codable {
    public var mappedDesign: LogicDesignReference?
    public var mappedCellCount: Int
    public var loweredNodeCount: Int
    public var optimizedNodeCount: Int
    public var totalArea: Double
    public var totalPower: Double
    public var provenance: XcircuiteFileReference?
    public var equivalenceRequest: XcircuiteFileReference?
    public var equivalenceRequired: Bool
    public var acceptanceState: LogicSynthesisAcceptanceState

    public init(
        mappedDesign: LogicDesignReference?,
        mappedCellCount: Int,
        loweredNodeCount: Int = 0,
        optimizedNodeCount: Int = 0,
        totalArea: Double = 0,
        totalPower: Double = 0,
        provenance: XcircuiteFileReference? = nil,
        equivalenceRequest: XcircuiteFileReference? = nil,
        equivalenceRequired: Bool = true,
        acceptanceState: LogicSynthesisAcceptanceState = .pendingEquivalence
    ) {
        self.mappedDesign = mappedDesign
        self.mappedCellCount = mappedCellCount
        self.loweredNodeCount = loweredNodeCount
        self.optimizedNodeCount = optimizedNodeCount
        self.totalArea = totalArea
        self.totalPower = totalPower
        self.provenance = provenance
        self.equivalenceRequest = equivalenceRequest
        self.equivalenceRequired = equivalenceRequired
        self.acceptanceState = acceptanceState
    }

    private enum CodingKeys: String, CodingKey {
        case mappedDesign
        case mappedCellCount
        case loweredNodeCount
        case optimizedNodeCount
        case totalArea
        case totalPower
        case provenance
        case equivalenceRequest
        case equivalenceRequired
        case acceptanceState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappedDesign = try container.decodeIfPresent(LogicDesignReference.self, forKey: .mappedDesign)
        mappedCellCount = try container.decode(Int.self, forKey: .mappedCellCount)
        loweredNodeCount = try container.decodeIfPresent(Int.self, forKey: .loweredNodeCount) ?? mappedCellCount
        optimizedNodeCount = try container.decodeIfPresent(Int.self, forKey: .optimizedNodeCount) ?? mappedCellCount
        totalArea = try container.decodeIfPresent(Double.self, forKey: .totalArea) ?? 0
        totalPower = try container.decodeIfPresent(Double.self, forKey: .totalPower) ?? 0
        provenance = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .provenance)
        equivalenceRequest = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .equivalenceRequest)
        equivalenceRequired = try container.decodeIfPresent(Bool.self, forKey: .equivalenceRequired) ?? true
        acceptanceState = try container.decodeIfPresent(LogicSynthesisAcceptanceState.self, forKey: .acceptanceState)
            ?? .pendingEquivalence
    }
}
