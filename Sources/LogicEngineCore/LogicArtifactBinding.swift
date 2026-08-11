import CircuiteFoundation
import Foundation

public enum LogicArtifactBindingError: Error, Sendable, Equatable {
    case availabilityIdentityMismatch
    case localAvailabilityRequired
    case missingWorkspaceRoot
    case missingOutputRoot
    case unsupportedLocalRoot(String)
}

/// Binds location-independent content identity to one execution-scoped availability.
public struct LogicArtifactBinding: Sendable, Hashable, Codable {
    public static let workspaceRootIdentifier = "logic-workspace"
    public static let outputRootIdentifier = "logic-output"
    public static let localFileSystemRootIdentifier = "logic-local-file-system"

    public let reference: ArtifactReference
    public let availability: ArtifactAvailability

    public var id: ArtifactID { reference.id }
    public var digest: ContentDigest { reference.digest }
    public var byteCount: UInt64 { reference.byteCount }
    public var descriptor: ArtifactDescriptor { reference.descriptor }

    public init(
        reference: ArtifactReference,
        availability: ArtifactAvailability
    ) throws {
        guard reference.id == availability.artifactID else {
            throw LogicArtifactBindingError.availabilityIdentityMismatch
        }
        self.reference = reference
        self.availability = availability
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reference: container.decode(ArtifactReference.self, forKey: .reference),
            availability: container.decode(ArtifactAvailability.self, forKey: .availability)
        )
    }

    public static func local(
        reference: ArtifactReference,
        fileURL: URL
    ) throws -> Self {
        guard fileURL.isFileURL else {
            throw LogicArtifactBindingError.localAvailabilityRequired
        }
        return try Self(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: localFileSystemRootIdentifier),
                relativePath: try absoluteRelativePath(for: fileURL)
            )
        )
    }

    public var materializationDescription: String {
        switch availability {
        case .local(_, let rootID, let relativePath):
            return "local:\(rootID.rawValue)/\(relativePath.stringValue)"
        case .service(_, let resource):
            return "service:\(resource)"
        }
    }

    public func localFileURL(
        relativeTo workspaceRoot: URL,
        outputRoot: URL?
    ) throws -> URL {
        guard case .local(_, let rootID, let relativePath) = availability else {
            throw LogicArtifactBindingError.localAvailabilityRequired
        }
        let root: URL
        switch rootID.rawValue {
        case Self.workspaceRootIdentifier:
            root = workspaceRoot
        case Self.outputRootIdentifier:
            guard let outputRoot else {
                throw LogicArtifactBindingError.missingOutputRoot
            }
            root = outputRoot
        case Self.localFileSystemRootIdentifier:
            root = URL(filePath: "/", directoryHint: .isDirectory)
        default:
            throw LogicArtifactBindingError.unsupportedLocalRoot(rootID.rawValue)
        }
        return relativePath.segments.reduce(root.standardizedFileURL) {
            partial, segment in
            partial.appending(path: segment)
        }
    }

    public static func require(
        _ reference: ArtifactReference,
        in bindings: [LogicArtifactBinding]
    ) throws -> LogicArtifactBinding {
        guard let binding = bindings.first(where: { $0.reference == reference }) else {
            throw LogicExecutionError.missingArtifact(reference.id.description)
        }
        return binding
    }

    private static func absoluteRelativePath(for fileURL: URL) throws -> ArtifactRelativePath {
        try ArtifactRelativePath(
            segments: fileURL.standardizedFileURL.path(percentEncoded: false)
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
        )
    }
}
