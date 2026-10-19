import CircuiteFoundation
import TimingCore

/// Explicitly expands one exact source-cell premise to all mapped instances in its scope.
public struct LogicOperatingConditionPolicy: Sendable, Hashable, Codable {
    public let library: ArtifactReference
    public let cell: String
    /// Nil denotes source-only functional execution, never an inferred timing corner.
    public let cornerID: String?
    public let conditions: [LibertyPGCondition]

    public init(library: ArtifactReference, cell: String, cornerID: String? = nil, conditions: [LibertyPGCondition]) {
        self.library = library; self.cell = cell; self.cornerID = cornerID; self.conditions = conditions
    }
}
