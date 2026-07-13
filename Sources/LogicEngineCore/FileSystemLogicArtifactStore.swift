import CircuiteFoundation
import Foundation

public struct FileSystemLogicArtifactStore: LogicArtifactStoring {
    public let rootDirectory: URL
    public let defaultOutputDirectory: URL?
    private let digester: SHA256ContentDigester

    public init(
        rootDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        defaultOutputDirectory: URL? = nil,
        digester: SHA256ContentDigester = SHA256ContentDigester()
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.defaultOutputDirectory = defaultOutputDirectory?.standardizedFileURL
        self.digester = digester
    }

    public func read(_ reference: ArtifactReference) throws -> Data {
        let path = reference.locator.location.value
        let url = try reference.locator.location.resolvedFileURL(relativeTo: rootDirectory)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw LogicExecutionError.missingArtifact(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LogicExecutionError.unreadableArtifact("\(path): \(error.localizedDescription)")
        }
        let actualDigest = try digester.digest(data: data, using: .sha256)
        if actualDigest != reference.digest {
            throw LogicExecutionError.artifactDigestMismatch(path)
        }
        if UInt64(data.count) != reference.byteCount {
            throw LogicExecutionError.artifactByteCountMismatch(path)
        }
        return data
    }

    public func write(
        _ data: Data,
        fileName: String,
        outputDirectory: String?,
        runID: String,
        artifactID: String?,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        let directory = try resolveOutputDirectory(outputDirectory, runID: runID)
        let destination = directory.appending(path: fileName).standardizedFileURL
        let parentPath = URL(
            fileURLWithPath: destination.deletingLastPathComponent().path(percentEncoded: false),
            isDirectory: true
        ).standardizedFileURL.path(percentEncoded: false)
        let directoryPath = URL(
            fileURLWithPath: directory.path(percentEncoded: false),
            isDirectory: true
        ).standardizedFileURL.path(percentEncoded: false)
        guard parentPath == directoryPath else {
            throw LogicExecutionError.artifactWriteFailed("output file escapes the run directory")
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch {
            throw LogicExecutionError.artifactWriteFailed(error.localizedDescription)
        }
        let path = relativeOrAbsolutePath(destination)
        let location: ArtifactLocation
        do {
            if path.hasPrefix("/") {
                location = try ArtifactLocation(fileURL: destination)
            } else {
                location = try ArtifactLocation(workspaceRelativePath: path)
            }
        } catch {
            throw LogicExecutionError.invalidArtifact(path)
        }
        let id: ArtifactID?
        if let artifactID {
            do { id = try ArtifactID(rawValue: artifactID) }
            catch { throw LogicExecutionError.invalidArtifact("invalid artifact ID: \(artifactID)") }
        } else {
            id = nil
        }
        return ArtifactReference(
            id: id,
            locator: ArtifactLocator(location: location, role: .output, kind: kind, format: format),
            digest: try digester.digest(data: data, using: .sha256),
            byteCount: UInt64(data.count)
        )
    }

    private func resolveOutputDirectory(_ rawPath: String?, runID: String) throws -> URL {
        if let rawPath, !rawPath.isEmpty {
            let candidate = resolve(rawPath, relativeTo: rootDirectory)
            return candidate.standardizedFileURL
        }
        if let defaultOutputDirectory {
            return defaultOutputDirectory.appending(path: runID).standardizedFileURL
        }
        return rootDirectory
            .appending(path: ".logic-engine")
            .appending(path: "runs")
            .appending(path: runID)
            .standardizedFileURL
    }

    private func resolve(_ rawPath: String, relativeTo base: URL) -> URL {
        let candidate = URL(fileURLWithPath: rawPath, relativeTo: base)
        return candidate.standardizedFileURL
    }

    private func relativeOrAbsolutePath(_ url: URL) -> String {
        let rootPath = rootDirectory.path(percentEncoded: false)
        if rootPath == "/" {
            return url.path(percentEncoded: false)
        }
        let base = rootPath.hasSuffix("/")
            ? rootPath
            : rootPath + "/"
        let path = url.path(percentEncoded: false)
        if path.hasPrefix(base) {
            return String(path.dropFirst(base.count))
        }
        return path
    }
}
