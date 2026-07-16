import Foundation

/// Errors raised when a logic domain value cannot be projected into the
/// CircuiteFoundation contract without losing integrity or provenance.
public enum LogicFoundationBoundaryError: Error, Sendable, Equatable, Hashable, LocalizedError {
    case missingArtifactDigest(String)
    case invalidArtifactDigest(String)
    case invalidArtifactLocation(String, reason: String)
    case byteCountOutOfRange(String)
    case invalidArtifactIdentity(String)
    case unsupportedArtifactFormat(String)
    case invalidDiagnosticCode(String)
    case invalidProducerIdentity(String)
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .missingArtifactDigest(let path):
            "Logic artifact has no digest at the Foundation boundary: \(path)"
        case .invalidArtifactDigest(let path):
            "Logic artifact has an invalid digest at the Foundation boundary: \(path)"
        case .invalidArtifactLocation(let path, let reason):
            "Logic artifact location is invalid for '\(path)': \(reason)"
        case .byteCountOutOfRange(let path):
            "Logic artifact byte count cannot be represented: \(path)"
        case .invalidArtifactIdentity(let identity):
            "Logic artifact identity is invalid: \(identity)"
        case .unsupportedArtifactFormat(let format):
            "Logic artifact format is not supported by the Foundation boundary: \(format)"
        case .invalidDiagnosticCode(let code):
            "Logic diagnostic code is invalid at the Foundation boundary: \(code)"
        case .invalidProducerIdentity(let identity):
            "Logic producer identity is invalid: \(identity)"
        case .invalidRequest(let message):
            "Logic Foundation request is invalid: \(message)"
        }
    }
}
