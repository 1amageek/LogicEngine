import Foundation
import LogicEngineCore
import XcircuitePackage

public struct LogicSynthesisEquivalenceEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    public let sourceDesignDigest: String
    public let mappedDesignDigest: String
    public let proofScope: String
    public let status: LogicEquivalenceEvidenceStatus
    public let proofArtifact: XcircuiteFileReference?

    public init(
        runID: String,
        sourceDesignDigest: String,
        mappedDesignDigest: String,
        proofScope: String,
        status: LogicEquivalenceEvidenceStatus,
        proofArtifact: XcircuiteFileReference? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.sourceDesignDigest = sourceDesignDigest
        self.mappedDesignDigest = mappedDesignDigest
        self.proofScope = proofScope
        self.status = status
        self.proofArtifact = proofArtifact
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
                  !proofArtifact.path.isEmpty,
                  proofArtifact.sha256?.isEmpty == false,
                  proofArtifact.byteCount.map({ $0 > 0 }) == true else {
                throw LogicExecutionError.missingPrerequisite(
                    "proved equivalence evidence requires an integrity-bearing proof artifact"
                )
            }
        }
    }
}
