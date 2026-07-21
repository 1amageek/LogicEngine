import Foundation
import LogicEngineCore
import CircuiteFoundation

public struct LogicSynthesisEquivalenceEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let runID: String
    public let sourceDesignDigest: String
    public let mappedDesignDigest: String
    public let proofScope: String
    public let status: LogicEquivalenceEvidenceStatus
    public let proofArtifact: ArtifactReference?
    public let provenance: ExecutionProvenance

    public init(
        runID: String,
        sourceDesignDigest: String,
        mappedDesignDigest: String,
        proofScope: String,
        status: LogicEquivalenceEvidenceStatus,
        proofArtifact: ArtifactReference? = nil,
        provenance: ExecutionProvenance
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.sourceDesignDigest = sourceDesignDigest
        self.mappedDesignDigest = mappedDesignDigest
        self.proofScope = proofScope
        self.status = status
        self.proofArtifact = proofArtifact
        self.provenance = provenance
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact(
                "unsupported synthesis equivalence evidence schema version \(schemaVersion)"
            )
        }
        guard !runID.isEmpty,
              !sourceDesignDigest.isEmpty,
              !mappedDesignDigest.isEmpty,
              !proofScope.isEmpty else {
            throw LogicExecutionError.invalidArtifact(
                "synthesis equivalence evidence has an empty identity field"
            )
        }
        if status == .proved {
            guard let proofArtifact,
                  !proofArtifact.locator.location.value.isEmpty,
                  !proofArtifact.digest.hexadecimalValue.isEmpty,
                  proofArtifact.byteCount > 0 else {
                throw LogicExecutionError.missingPrerequisite(
                    "proved equivalence evidence requires an integrity-bearing proof artifact"
                )
            }
        }
    }
}
