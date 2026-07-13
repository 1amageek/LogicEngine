import Foundation
import XcircuitePackage

public struct FileSystemLogicArtifactStore: LogicArtifactStoring {
    public let rootDirectory: URL
    public let defaultOutputDirectory: URL?
    private let hasher: XcircuiteHasher

    public init(
        rootDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        defaultOutputDirectory: URL? = nil,
        hasher: XcircuiteHasher = XcircuiteHasher()
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.defaultOutputDirectory = defaultOutputDirectory?.standardizedFileURL
        self.hasher = hasher
    }

    public func read(_ reference: XcircuiteFileReference) throws -> Data {
        let url = resolve(reference.path, relativeTo: rootDirectory)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw LogicExecutionError.missingArtifact(reference.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LogicExecutionError.unreadableArtifact("\(reference.path): \(error.localizedDescription)")
        }
        if let expectedDigest = reference.sha256, hasher.sha256(data: data) != expectedDigest {
            throw LogicExecutionError.artifactDigestMismatch(reference.path)
        }
        if let expectedByteCount = reference.byteCount, Int64(data.count) != expectedByteCount {
            throw LogicExecutionError.artifactByteCountMismatch(reference.path)
        }
        return data
    }

    public func write(
        _ data: Data,
        fileName: String,
        outputDirectory: String?,
        runID: String,
        artifactID: String?,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
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
        return XcircuiteFileReference(
            artifactID: artifactID,
            path: path,
            kind: kind,
            format: format,
            sha256: hasher.sha256(data: data),
            byteCount: Int64(data.count),
            producedByRunID: runID
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
