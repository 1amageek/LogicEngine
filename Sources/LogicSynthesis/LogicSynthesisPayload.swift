import Foundation
import CircuiteFoundation
import LogicIR
import PowerIntent
import TimingCore
import PDKCore
import LogicEngineCore
import CircuiteFoundation

public struct LogicSynthesisPayload: Sendable, Hashable, Codable {
    public var mappedDesign: LogicFoundationDesignReference?
    public var mappedCellCount: Int
    public var loweredNodeCount: Int
    public var optimizedNodeCount: Int
    public var totalArea: Double
    public var totalPower: Double
    public var provenance: ArtifactReference?
    public var equivalenceRequest: ArtifactReference?
    public var equivalenceRequired: Bool
    public var acceptanceState: LogicSynthesisAcceptanceState

    public init(
        mappedDesign: LogicFoundationDesignReference?,
        mappedCellCount: Int,
        loweredNodeCount: Int = 0,
        optimizedNodeCount: Int = 0,
        totalArea: Double = 0,
        totalPower: Double = 0,
        provenance: ArtifactReference? = nil,
        equivalenceRequest: ArtifactReference? = nil,
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
        mappedDesign = try container.decodeIfPresent(LogicFoundationDesignReference.self, forKey: .mappedDesign)
        mappedCellCount = try container.decode(Int.self, forKey: .mappedCellCount)
        loweredNodeCount = try container.decode(Int.self, forKey: .loweredNodeCount)
        optimizedNodeCount = try container.decode(Int.self, forKey: .optimizedNodeCount)
        totalArea = try container.decode(Double.self, forKey: .totalArea)
        totalPower = try container.decode(Double.self, forKey: .totalPower)
        provenance = try container.decodeIfPresent(ArtifactReference.self, forKey: .provenance)
        equivalenceRequest = try container.decodeIfPresent(ArtifactReference.self, forKey: .equivalenceRequest)
        equivalenceRequired = try container.decode(Bool.self, forKey: .equivalenceRequired)
        acceptanceState = try container.decode(LogicSynthesisAcceptanceState.self, forKey: .acceptanceState)
    }
}
