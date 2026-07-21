import Foundation
import LogicEngineCore
import LogicIR
import CircuiteFoundation

public struct LogicSynthesisEquivalenceRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let runID: String
    public let topDesignName: String
    public let sourceDesign: LogicDesignReference
    public let mappedDesign: LogicDesignReference
    public let synthesisProvenance: ArtifactReference
    public let pdkArtifact: ArtifactReference
    public let proofScope: String

    public init(
        runID: String,
        topDesignName: String,
        sourceDesign: LogicDesignReference,
        mappedDesign: LogicDesignReference,
        synthesisProvenance: ArtifactReference,
        pdkArtifact: ArtifactReference,
        proofScope: String = "rtl-to-mapped-structural"
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.topDesignName = topDesignName
        self.sourceDesign = sourceDesign
        self.mappedDesign = mappedDesign
        self.synthesisProvenance = synthesisProvenance
        self.pdkArtifact = pdkArtifact
        self.proofScope = proofScope
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact(
                "unsupported synthesis equivalence request schema version \(schemaVersion)"
            )
        }
        guard !runID.isEmpty, !topDesignName.isEmpty else {
            throw LogicExecutionError.invalidArtifact(
                "synthesis equivalence request requires run ID and top design name"
            )
        }
        guard sourceDesign.topDesignName == topDesignName,
              mappedDesign.topDesignName == topDesignName else {
            throw LogicExecutionError.invalidDesign(
                "synthesis equivalence references must use the request top design"
            )
        }
        guard !sourceDesign.designDigest.isEmpty,
              !mappedDesign.designDigest.isEmpty else {
            throw LogicExecutionError.invalidArtifact(
                "synthesis equivalence references must carry design digests"
            )
        }
        guard pdkArtifact.digest.algorithm == .sha256,
              pdkArtifact.byteCount > 0 else {
            throw LogicExecutionError.invalidArtifact(
                "synthesis equivalence requires an integrity-bearing PDK artifact"
            )
        }
        guard !proofScope.isEmpty else {
            throw LogicExecutionError.invalidArtifact("synthesis equivalence proof scope is empty")
        }
    }
}
