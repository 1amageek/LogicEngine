import CircuiteFoundation
import LogicEngineCore

public struct LogicEngineCapabilities: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public let schemaVersion: SchemaVersion
    public let lowering: LogicLoweringCapabilities
    public let simulation: LogicSimulationCapabilities
    public let synthesis: LogicSynthesisCapabilities
    public let equivalence: LogicEquivalenceCapabilities
    public let evidence: LogicEvidenceCapabilities

    public init(
        schemaVersion: SchemaVersion = Self.currentSchemaVersion,
        lowering: LogicLoweringCapabilities,
        simulation: LogicSimulationCapabilities,
        synthesis: LogicSynthesisCapabilities,
        equivalence: LogicEquivalenceCapabilities,
        evidence: LogicEvidenceCapabilities
    ) {
        self.schemaVersion = schemaVersion
        self.lowering = lowering
        self.simulation = simulation
        self.synthesis = synthesis
        self.equivalence = equivalence
        self.evidence = evidence
    }

    public static let native = Self(
        lowering: .native,
        simulation: .native,
        synthesis: .native,
        equivalence: .native,
        evidence: .native
    )

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact(
                "unsupported LogicEngine capabilities schema version \(schemaVersion)"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case lowering
        case simulation
        case synthesis
        case equivalence
        case evidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
        lowering = try container.decode(LogicLoweringCapabilities.self, forKey: .lowering)
        simulation = try container.decode(LogicSimulationCapabilities.self, forKey: .simulation)
        synthesis = try container.decode(LogicSynthesisCapabilities.self, forKey: .synthesis)
        equivalence = try container.decode(LogicEquivalenceCapabilities.self, forKey: .equivalence)
        evidence = try container.decode(LogicEvidenceCapabilities.self, forKey: .evidence)
        try validate()
    }
}
