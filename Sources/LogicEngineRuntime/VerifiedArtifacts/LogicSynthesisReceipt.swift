import CircuiteFoundation
import LogicEngineCore

public struct LogicSynthesisReceipt: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 4
    public static let algorithmIdentity = "logic.actual-cell.synthesis.v7"
    public let schemaVersion: Int
    public let algorithm: String
    public let producer: ProducerIdentity
    public let realizationPolicy: LogicSynthesisRealizationPolicy
    public let seed: UInt64
    public let request: LogicArtifactBinding
    public let originalBitDesign: LogicArtifactBinding
    public let mappedIdentities: LogicArtifactBinding
    public let netlist: LogicArtifactBinding
    public let proof: LogicArtifactBinding
    public let timingResult: LogicArtifactBinding?
    public let operatingConditions: LogicOperatingConditionReceipt
    public let instanceCount: Int
    public let area: Double
    public let combinationalDepth: Int
    public let proofKind: String
    internal init(producer: ProducerIdentity, realizationPolicy: LogicSynthesisRealizationPolicy, request: LogicArtifactBinding, originalBitDesign: LogicArtifactBinding,
                  mappedIdentities: LogicArtifactBinding, netlist: LogicArtifactBinding, proof: LogicArtifactBinding,
                  timingResult: LogicArtifactBinding?, operatingConditions: LogicOperatingConditionReceipt,
                  instanceCount: Int, area: Double,
                  combinationalDepth: Int, proofKind: String) {
        schemaVersion = Self.currentSchemaVersion; algorithm = Self.algorithmIdentity
        self.producer = producer; self.realizationPolicy = realizationPolicy; seed = 0
        self.request = request; self.originalBitDesign = originalBitDesign; self.mappedIdentities = mappedIdentities
        self.netlist = netlist; self.proof = proof; self.timingResult = timingResult
        self.operatingConditions = operatingConditions
        self.instanceCount = instanceCount; self.area = area; self.combinationalDepth = combinationalDepth; self.proofKind = proofKind
    }
    public var artifacts: [LogicArtifactBinding] {
        [request, originalBitDesign, mappedIdentities, netlist, proof] + (timingResult.map { [$0] } ?? [])
    }
}
