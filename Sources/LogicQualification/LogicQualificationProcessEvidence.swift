import Foundation

public struct LogicQualificationProcessEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var qualificationID: String
    public var suiteID: String
    public var processID: String
    public var pdkID: String
    public var pdkDigest: String
    public var toolImplementationID: String
    public var toolImplementationVersion: String
    public var environmentIdentity: String
    public var inputArtifactIDs: [String]
    public var outputArtifactIDs: [String]
    public var inputArtifactDigests: [String: String]
    public var outputArtifactDigests: [String: String]
    public var metrics: [String: Double]
    public var failures: [String]
    public var qualified: Bool
    public var checkedAt: Date

    public init(
        qualificationID: String,
        suiteID: String,
        processID: String,
        pdkID: String,
        pdkDigest: String,
        toolImplementationID: String,
        toolImplementationVersion: String,
        environmentIdentity: String,
        inputArtifactIDs: [String],
        outputArtifactIDs: [String],
        inputArtifactDigests: [String: String] = [:],
        outputArtifactDigests: [String: String] = [:],
        metrics: [String: Double] = [:],
        failures: [String] = [],
        qualified: Bool,
        checkedAt: Date = Date(),
        schemaVersion: Int = LogicQualificationProcessEvidence.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.suiteID = suiteID
        self.processID = processID
        self.pdkID = pdkID
        self.pdkDigest = pdkDigest
        self.toolImplementationID = toolImplementationID
        self.toolImplementationVersion = toolImplementationVersion
        self.environmentIdentity = environmentIdentity
        self.inputArtifactIDs = Array(Set(inputArtifactIDs)).sorted()
        self.outputArtifactIDs = Array(Set(outputArtifactIDs)).sorted()
        self.inputArtifactDigests = inputArtifactDigests
        self.outputArtifactDigests = outputArtifactDigests
        self.metrics = metrics
        self.failures = Array(Set(failures)).sorted()
        self.qualified = qualified
        self.checkedAt = checkedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case qualificationID
        case suiteID
        case processID
        case pdkID
        case pdkDigest
        case toolImplementationID
        case toolImplementationVersion
        case environmentIdentity
        case inputArtifactIDs
        case outputArtifactIDs
        case inputArtifactDigests
        case outputArtifactDigests
        case metrics
        case failures
        case qualified
        case checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        qualificationID = try container.decode(String.self, forKey: .qualificationID)
        suiteID = try container.decode(String.self, forKey: .suiteID)
        processID = try container.decode(String.self, forKey: .processID)
        pdkID = try container.decode(String.self, forKey: .pdkID)
        pdkDigest = try container.decode(String.self, forKey: .pdkDigest)
        toolImplementationID = try container.decode(String.self, forKey: .toolImplementationID)
        toolImplementationVersion = try container.decode(String.self, forKey: .toolImplementationVersion)
        environmentIdentity = try container.decode(String.self, forKey: .environmentIdentity)
        inputArtifactIDs = try container.decode([String].self, forKey: .inputArtifactIDs)
        outputArtifactIDs = try container.decode([String].self, forKey: .outputArtifactIDs)
        inputArtifactDigests = try container.decodeIfPresent([String: String].self, forKey: .inputArtifactDigests) ?? [:]
        outputArtifactDigests = try container.decodeIfPresent([String: String].self, forKey: .outputArtifactDigests) ?? [:]
        metrics = try container.decodeIfPresent([String: Double].self, forKey: .metrics) ?? [:]
        failures = try container.decodeIfPresent([String].self, forKey: .failures) ?? []
        qualified = try container.decode(Bool.self, forKey: .qualified)
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(qualificationID, forKey: .qualificationID)
        try container.encode(suiteID, forKey: .suiteID)
        try container.encode(processID, forKey: .processID)
        try container.encode(pdkID, forKey: .pdkID)
        try container.encode(pdkDigest, forKey: .pdkDigest)
        try container.encode(toolImplementationID, forKey: .toolImplementationID)
        try container.encode(toolImplementationVersion, forKey: .toolImplementationVersion)
        try container.encode(environmentIdentity, forKey: .environmentIdentity)
        try container.encode(inputArtifactIDs, forKey: .inputArtifactIDs)
        try container.encode(outputArtifactIDs, forKey: .outputArtifactIDs)
        try container.encode(inputArtifactDigests, forKey: .inputArtifactDigests)
        try container.encode(outputArtifactDigests, forKey: .outputArtifactDigests)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(failures, forKey: .failures)
        try container.encode(qualified, forKey: .qualified)
        try container.encode(checkedAt, forKey: .checkedAt)
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicQualificationError.invalidProcessEvidence(
                "unsupported process evidence schema version \(schemaVersion)"
            )
        }
        let requiredValues = [
            qualificationID,
            suiteID,
            processID,
            pdkID,
            pdkDigest,
            toolImplementationID,
            toolImplementationVersion,
            environmentIdentity,
        ]
        guard requiredValues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LogicQualificationError.invalidProcessEvidence(
                "process evidence identity is incomplete"
            )
        }
        guard pdkDigest.count == 64,
              pdkDigest.allSatisfy(\.isHexDigit) else {
            throw LogicQualificationError.invalidProcessEvidence(
                "process evidence PDK digest must be a SHA-256 hex digest"
            )
        }
        guard !inputArtifactIDs.isEmpty, !outputArtifactIDs.isEmpty else {
            throw LogicQualificationError.invalidProcessEvidence(
                "process evidence must identify input and output artifacts"
            )
        }
        let inputIDs = Set(inputArtifactIDs)
        let outputIDs = Set(outputArtifactIDs)
        guard Set(inputArtifactDigests.keys).isSubset(of: inputIDs),
              Set(outputArtifactDigests.keys).isSubset(of: outputIDs) else {
            throw LogicQualificationError.invalidProcessEvidence(
                "process evidence contains a digest for an unknown artifact"
            )
        }
        let allDigests = Array(inputArtifactDigests.values) + Array(outputArtifactDigests.values)
        guard allDigests.allSatisfy(Self.isSHA256Digest) else {
            throw LogicQualificationError.invalidProcessEvidence(
                "process evidence artifact digests must be SHA-256 hex digests"
            )
        }
        if qualified {
            guard Set(inputArtifactDigests.keys) == inputIDs,
                  Set(outputArtifactDigests.keys) == outputIDs else {
                throw LogicQualificationError.invalidProcessEvidence(
                    "qualified process evidence must digest every input and output artifact"
                )
            }
            guard inputArtifactDigests.values.contains(pdkDigest) else {
                throw LogicQualificationError.invalidProcessEvidence(
                    "qualified process evidence must bind an input artifact to the PDK digest"
                )
            }
        }
        guard metrics.values.allSatisfy(\.isFinite) else {
            throw LogicQualificationError.invalidProcessEvidence(
                "process evidence contains a non-finite metric"
            )
        }
        guard failures.isEmpty || !qualified else {
            throw LogicQualificationError.invalidProcessEvidence(
                "qualified process evidence cannot contain failures"
            )
        }
    }

    private static func isSHA256Digest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    public func isUsable(
        for report: LogicQualificationReport
    ) -> Bool {
        do {
            try validate()
        } catch {
            return false
        }
        return qualified
            && suiteID == report.suiteID
            && toolImplementationID == report.implementationID
            && [
                LogicQualificationState.oracleCorrelated,
                .processQualified,
                .releaseEligible,
            ].contains(report.state)
    }
}
