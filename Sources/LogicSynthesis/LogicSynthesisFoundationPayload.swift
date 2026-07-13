import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Foundation-native synthesis metrics, lineage, and acceptance references.
public struct LogicSynthesisFoundationPayload: Sendable, Hashable, Codable {
    public let mappedDesign: LogicFoundationDesignReference?
    public let mappedCellCount: Int
    public let loweredNodeCount: Int
    public let optimizedNodeCount: Int
    public let totalArea: Double
    public let totalPower: Double
    public let provenance: ArtifactReference?
    public let equivalenceRequest: ArtifactReference?
    public let equivalenceRequired: Bool
    public let acceptanceState: LogicSynthesisAcceptanceState

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
}
