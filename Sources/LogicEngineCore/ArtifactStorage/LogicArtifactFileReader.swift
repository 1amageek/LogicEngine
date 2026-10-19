import Darwin
import Foundation

package enum LogicArtifactFileReader {
    package static func read(_ url: URL, maximumBytes: UInt64, expectedBytes: UInt64? = nil) throws -> Data {
        guard maximumBytes < UInt64(Int.max) else {
            throw LogicExecutionError.unreadableArtifact("Read limit exceeds host addressing")
        }
        // The handle exclusively owns the descriptor. Nonblocking open prevents a FIFO
        // from suspending before fstat can reject it; no descriptor escapes this scope.
        let descriptor = Darwin.open(url.path(percentEncoded: false), O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw LogicExecutionError.unreadableArtifact("Could not open \(url.lastPathComponent): \(String(cString: strerror(errno)))")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let data: Data
        do {
            var status = stat()
            guard Darwin.fstat(descriptor, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFREG, status.st_size >= 0 else {
                throw LogicExecutionError.unreadableArtifact("Input must be a regular file: \(url.lastPathComponent)")
            }
            let size = UInt64(status.st_size)
            if let expectedBytes, size != expectedBytes {
                throw LogicExecutionError.artifactByteCountMismatch(url.lastPathComponent)
            }
            guard size <= maximumBytes else {
                throw LogicExecutionError.invalidArtifact("File exceeds read limit of \(maximumBytes) bytes: \(url.lastPathComponent)")
            }
            var buffer = Data()
            while buffer.count <= Int(size) {
                let remaining = Int(size) - buffer.count + 1
                guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else { break }
                guard chunk.count <= Int(size) - buffer.count else {
                    throw LogicExecutionError.artifactByteCountMismatch(url.lastPathComponent)
                }
                buffer.append(chunk)
            }
            guard buffer.count == Int(size) else {
                throw LogicExecutionError.artifactByteCountMismatch(url.lastPathComponent)
            }
            data = buffer
        } catch {
            do { try handle.close() }
            catch let close { throw LogicExecutionError.unreadableArtifact("Read and close failed: \(error); \(close)") }
            throw error
        }
        try handle.close()
        return data
    }
}
