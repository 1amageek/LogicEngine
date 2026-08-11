import CircuiteFoundation
import CircuiteFoundationCrypto

public enum LogicEvidenceManifestFactory {
    public static func make(
        provenance: ExecutionProvenance,
        artifacts: [ArtifactReference]
    ) throws -> EvidenceManifest {
        try EvidenceManifest.contentAddressed(
            provenance: provenance,
            artifacts: artifacts,
            digester: SHA256ContentDigester()
        )
    }
}
