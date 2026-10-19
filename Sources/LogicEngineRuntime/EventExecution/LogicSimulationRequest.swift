import CircuiteFoundation
import LogicEngineCore
import LogicKernelCore

public struct LogicSimulationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion(major: 4, minor: 0, patch: 0)
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let sources: [LogicSourceInput]
    public let roots: [String]
    public let top: String
    public let mappedReceipt: LogicArtifactBinding?
    public let specification: LogicArtifactBinding?
    public let events: [LogicSimulationEventRecord]
    public let limits: LogicRuntimeLimits
    public var artifactDirectory: String?
    public var designInputs: [ArtifactReference] { sources.map { $0.artifact.reference } + (mappedReceipt.map { [$0.reference] } ?? []) }
    public var inputs: [ArtifactReference] { designInputs + (specification.map { [$0.reference] } ?? []) }
    public init(runID: String, sources: [LogicSourceInput] = [], roots: [String] = [], top: String = "",
                mappedReceipt: LogicArtifactBinding? = nil, specification: LogicArtifactBinding? = nil, events: [LogicSimulationEventRecord],
                limits: LogicRuntimeLimits, artifactDirectory: String? = nil) {
        schemaVersion = Self.currentSchemaVersion; self.runID = runID; self.sources = sources
        self.roots = roots; self.top = top; self.mappedReceipt = mappedReceipt; self.specification = specification; self.events = events
        self.limits = limits; self.artifactDirectory = artifactDirectory
    }
    public func validate() throws(LogicKernelError) {
        guard schemaVersion == Self.currentSchemaVersion, !runID.isEmpty,
              runID.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95 }) else {
            throw .invalidInput("Invalid simulation run/schema")
        }
        if mappedReceipt != nil {
            guard sources.isEmpty, roots.isEmpty, top.isEmpty else { throw .invalidInput("Mapped simulation has conflicting source inputs") }
        } else {
            guard !sources.isEmpty, !roots.isEmpty, !top.isEmpty,
                  Set(sources.map(\.logicalName)).count == sources.count,
                  Set(roots).count == roots.count,
                  roots.allSatisfy({ root in sources.contains { $0.logicalName == root } }) else {
                throw .invalidInput("Source simulation requires exact unique roots")
            }
        }
        _ = try limits.kernelLimits()
    }
}
