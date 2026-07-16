import CircuiteFoundation
import Darwin
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
        self.rootDirectory = URL(
            fileURLWithPath: rootDirectory.standardizedFileURL.path(percentEncoded: false),
            isDirectory: true
        )
        self.defaultOutputDirectory = defaultOutputDirectory.map {
            URL(
                fileURLWithPath: $0.standardizedFileURL.path(percentEncoded: false),
                isDirectory: true
            )
        }
        self.digester = digester
    }

    public func read(_ reference: ArtifactReference) throws -> Data {
        let path = reference.locator.location.value
        let url: URL
        do {
            url = try reference.locator.location.resolvedFileURL(relativeTo: rootDirectory)
        } catch {
            throw LogicExecutionError.artifactReadOutsideRoot(path)
        }
        let canonicalRoot = rootDirectory.resolvingSymlinksInPath().standardizedFileURL
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard contains(canonicalURL, in: canonicalRoot) else {
            throw LogicExecutionError.artifactReadOutsideRoot(
                canonicalURL.path(percentEncoded: false)
            )
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw LogicExecutionError.missingArtifact(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: canonicalURL)
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
        let directory = try prepareOutputDirectory(outputDirectory, runID: runID)
        guard isSinglePathComponent(fileName) else {
            throw LogicExecutionError.invalidArtifact("output file name must be one path component: \(fileName)")
        }
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
        try persistImmutable(data, to: destination)
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

    private func prepareOutputDirectory(_ rawPath: String?, runID: String) throws -> URL {
        let candidate = try resolveOutputDirectory(rawPath, runID: runID)
        let outputRoot = defaultOutputDirectory ?? rootDirectory
        let resolvedOutputRoot = outputRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedCandidate, in: resolvedOutputRoot) else {
            throw LogicExecutionError.artifactOutputOutsideRoot(candidate.path(percentEncoded: false))
        }
        do {
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        } catch {
            throw LogicExecutionError.artifactWriteFailed(error.localizedDescription)
        }
        let canonicalRoot = outputRoot.resolvingSymlinksInPath().standardizedFileURL
        let canonicalCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(canonicalCandidate, in: canonicalRoot) else {
            throw LogicExecutionError.artifactSymlinkEscape(candidate.path(percentEncoded: false))
        }
        return canonicalCandidate
    }

    private func persistImmutable(_ data: Data, to destination: URL) throws {
        let destinationPath = destination.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: destinationPath) {
            try verifyExistingArtifact(data, at: destination)
            return
        }

        let temporary = destination.deletingLastPathComponent().appending(
            path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let temporaryPath = temporary.path(percentEncoded: false)
        let descriptor = Darwin.open(
            temporaryPath,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw LogicExecutionError.artifactWriteFailed(
                "could not create atomic temporary artifact at \(temporaryPath): \(posixErrorMessage())"
            )
        }
        defer {
            Darwin.close(descriptor)
            Darwin.unlink(temporaryPath)
        }

        try writeAll(data, to: descriptor, path: temporaryPath)
        guard Darwin.fsync(descriptor) == 0 else {
            throw LogicExecutionError.artifactWriteFailed(
                "could not synchronize atomic temporary artifact at \(temporaryPath): \(posixErrorMessage())"
            )
        }
        guard Darwin.link(temporaryPath, destinationPath) == 0 else {
            if errno == EEXIST {
                try verifyExistingArtifact(data, at: destination)
                return
            }
            throw LogicExecutionError.artifactWriteFailed(
                "could not publish atomic artifact at \(destinationPath): \(posixErrorMessage())"
            )
        }
    }

    private func verifyExistingArtifact(_ data: Data, at destination: URL) throws {
        let path = destination.path(percentEncoded: false)
        var status = stat()
        guard lstat(path, &status) == 0 else {
            throw LogicExecutionError.artifactWriteFailed(
                "could not inspect existing artifact at \(path): \(posixErrorMessage())"
            )
        }
        guard (status.st_mode & S_IFMT) != S_IFLNK else {
            throw LogicExecutionError.artifactSymlinkEscape(path)
        }
        let existing: Data
        do {
            existing = try Data(contentsOf: destination)
        } catch {
            throw LogicExecutionError.artifactWriteFailed(
                "could not read existing artifact at \(path): \(error.localizedDescription)"
            )
        }
        guard existing == data else {
            throw LogicExecutionError.artifactCollision(path)
        }
    }

    private func writeAll(_ data: Data, to descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                guard let baseAddress = rawBuffer.baseAddress else { return }
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0, errno == EINTR {
                    continue
                }
                throw LogicExecutionError.artifactWriteFailed(
                    "could not write atomic temporary artifact at \(path): \(posixErrorMessage())"
                )
            }
        }
    }

    private func contains(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = (root.standardizedFileURL.path(percentEncoded: false) as NSString).standardizingPath
        let candidatePath = (candidate.standardizedFileURL.path(percentEncoded: false) as NSString).standardizingPath
        if rootPath == "/" { return candidatePath.hasPrefix("/") }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath == rootPath || candidatePath.hasPrefix(prefix)
    }

    private func isSinglePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private func posixErrorMessage() -> String {
        String(cString: strerror(errno))
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
