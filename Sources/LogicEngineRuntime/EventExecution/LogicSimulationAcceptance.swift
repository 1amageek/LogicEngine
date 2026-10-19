import CircuiteFoundation
import LogicEngineCore

public struct LogicSimulationAcceptance: Sendable, Hashable, Codable {
    public static let algorithmIdentity = "logic.four-state.acceptance.v2"
    public let schemaVersion: Int
    public let algorithm: String
    public let producer: ProducerIdentity
    public let request: LogicArtifactBinding
    public let observations: LogicArtifactBinding
    public let specification: LogicArtifactBinding?
    public let operationalInputBindings: [LogicArtifactBinding]
    public let operationalInputs: [ArtifactReference]
    public let assessment: LogicSimulationAssessment
    internal init(producer: ProducerIdentity, request: LogicArtifactBinding, observations: LogicArtifactBinding,
                  specification: LogicArtifactBinding?, operationalInputs: [ArtifactReference],
                  operationalInputBindings: [LogicArtifactBinding], assessment: LogicSimulationAssessment) {
        schemaVersion = 2; algorithm = Self.algorithmIdentity; self.producer = producer
        self.request = request; self.observations = observations; self.specification = specification; self.operationalInputs = operationalInputs
        self.operationalInputBindings = operationalInputBindings; self.assessment = assessment
    }
}
