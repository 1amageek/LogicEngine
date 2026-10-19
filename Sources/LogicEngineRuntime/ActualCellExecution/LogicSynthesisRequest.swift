import CircuiteFoundation
import LogicEngineCore
import LogicKernelCore

public struct LogicSynthesisRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion(major: 7, minor: 0, patch: 0)
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let sources: [LogicSourceInput]
    public let roots: [String]
    public let top: String
    public let library: LogicArtifactBinding
    public let limits: LogicRuntimeLimits
    public let realizationPolicy: LogicSynthesisRealizationPolicy
    public let constraints: LogicSynthesisConstraints
    public let operatingConditionPolicies: [LogicOperatingConditionPolicy]
    public let operatingProcessScope: LogicOperatingProcessScope?
    public var artifactDirectory: String?
    public var inputs: [ArtifactReference] {
        let references = sources.map { $0.artifact.reference } + [library.reference]
            + (operatingProcessScope.map { $0.libraries.map { $0.artifact.reference } + [$0.pdkManifest.reference] } ?? [])
            + (constraints.timing.map { $0.libraries.map { $0.artifact.reference }
                + [$0.constraints.reference, $0.pdkManifest.reference] } ?? [])
        var seen = Set<ArtifactReference>()
        return references.filter { seen.insert($0).inserted }
    }
    public init(runID: String, sources: [LogicSourceInput], roots: [String], top: String,
                library: LogicArtifactBinding, limits: LogicRuntimeLimits,
                constraints: LogicSynthesisConstraints = .init(),
                realizationPolicy: LogicSynthesisRealizationPolicy = .standardNetlist,
                operatingConditionPolicies: [LogicOperatingConditionPolicy] = [],
                operatingProcessScope: LogicOperatingProcessScope? = nil, artifactDirectory: String? = nil) {
        schemaVersion = Self.currentSchemaVersion; self.runID = runID; self.sources = sources
        self.roots = roots; self.top = top; self.library = library; self.limits = limits
        self.realizationPolicy = realizationPolicy
        self.operatingConditionPolicies = operatingConditionPolicies
        self.operatingProcessScope = operatingProcessScope ?? constraints.timing?.operatingProcessScope
        self.constraints = constraints; self.artifactDirectory = artifactDirectory
    }
    public func validate() throws(LogicKernelError) {
        guard schemaVersion == Self.currentSchemaVersion, !runID.isEmpty,
              runID.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95 }),
              !sources.isEmpty, !top.isEmpty, !roots.isEmpty,
              Set(sources.map(\.logicalName)).count == sources.count,
              Set(roots).count == roots.count, roots.allSatisfy({ root in sources.contains { $0.logicalName == root } }),
              library.descriptor.format == .liberty else { throw .invalidInput("Invalid actual-cell synthesis request or schema") }
        _ = try limits.kernelLimits()
        if let scope = operatingProcessScope {
            guard !scope.processID.isEmpty, !scope.pdkVersion.isEmpty,
                  !scope.cornerIDs.isEmpty, !scope.libraries.isEmpty,
                  scope.characterizationBindings.count == scope.cornerIDs.count else {
                throw .invalidInput("Incomplete functional operating process scope")
            }
        }
        for (index, policy) in operatingConditionPolicies.enumerated() {
            guard policy.library == library.reference, !policy.cell.isEmpty, policy.cornerID != "",
                  operatingProcessScope.map({ scope in policy.cornerID.map(scope.cornerIDs.contains) ?? false }) ?? (policy.cornerID == nil) else {
                throw .invalidInput("Foreign source-cell policy or invalid source-only/timing scope")
            }
            for prior in operatingConditionPolicies[..<index] {
                guard prior.cell != policy.cell || prior.cornerID != policy.cornerID else { throw .invalidInput("Duplicate source-cell operating policy") }
            }
        }
        for value in [constraints.maximumArea, constraints.maximumPower] {
            guard value == nil || (value!.isFinite && value! >= 0) else { throw .invalidInput("Metric limits must be finite and nonnegative") }
        }
        if let timing = constraints.timing {
            guard operatingProcessScope == timing.operatingProcessScope else {
                throw .invalidInput("Requested timing differs from functional operating process scope")
            }
            guard !timing.cornerIDs.isEmpty, !timing.modeIDs.isEmpty, timing.maximumPaths > 0,
                  timing.characterizationBindings.count == timing.cornerIDs.count,
                  timing.libraries.allSatisfy({ $0.artifact.reference == library.reference }),
                  !timing.libraries.isEmpty else { throw .invalidInput("Timing requires exact mapping library and observed corner conditions") }
            for value in [timing.minimumSetupSlack, timing.minimumHoldSlack] {
                guard value == nil || value!.isFinite else { throw .invalidInput("Slack limits must be finite") }
            }
        }
    }
}
