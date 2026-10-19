import CircuiteFoundation
import LogicKernelCore
import TimingCore

extension NativeLogicTechnologyLibraryCompiler {
    internal func verifySource(_ source: borrowing OwnedLibertySource, identity: ArtifactID,
                               context: inout LogicKernelContext) throws(LogicLibraryCompilationError) {
        do throws(LogicKernelError) { try context.checkpoint() } catch { throw .kernel(error) }
        guard identity.digest.algorithm == .sha256 else { throw .digest(.unsupportedAlgorithm(identity.digest.algorithm)) }
        let size = UInt64(source.byteCount)
        guard size == identity.byteCount else { throw .sourceByteCountMismatch(expected: identity.byteCount, actual: size) }
        guard size > 0 else { throw .kernel(.invalidModel("Owned Liberty source is empty")) }
        let work = size.multipliedReportingOverflow(by: 2)
        guard !work.overflow else { throw .kernel(.invalidInput("Source hashing work overflows")) }
        let receipt: LogicStorageReservation
        do throws(LogicKernelError) {
            try context.charge(.workUnits, amount: work.partialValue)
            receipt = try context.reserveStorage(byteCount: size)
        } catch { throw .kernel(error) }
        let outcome: Result<ArtifactID, LogicLibraryCompilationError>
        do throws(LogicLibraryCompilationError) { outcome = .success(try hashSource(source, size: size)) }
        catch { outcome = .failure(error) }
        do throws(LogicKernelError) { try context.releaseStorage(receipt) }
        catch {
            if case .failure(let primary) = outcome { throw .cleanup(primary: primary, cause: error) }
            throw .kernel(error)
        }
        let actual = try outcome.get()
        do throws(LogicKernelError) { try context.checkpoint() } catch { throw .kernel(error) }
        guard actual == identity else { throw .sourceIdentityMismatch(expected: identity, actual: actual) }
    }

    private func hashSource(_ source: borrowing OwnedLibertySource, size: UInt64) throws(LogicLibraryCompilationError) -> ArtifactID {
        // ContentDigestUpdateLease currently borrows Array. This admitted host-boundary
        // copy ends before the caller releases its temporary-storage reservation.
        let bytes = source.withBytes { span in
            var bytes: [UInt8] = []; bytes.reserveCapacity(span.count)
            for index in span.indices { bytes.append(span[index]) }
            return bytes
        }
        let result: ContentDigestResult
        do throws(ContentDigestError) {
            result = try digester.digest(using: .sha256, limits: .init(maximumChunkByteCount: size,
                maximumTotalByteCount: size, maximumUpdateCount: 1)) { lease throws(ContentDigestError) in
                try lease.update(bytes)
            }
        } catch { throw .digest(error) }
        guard result.totalByteCount == size, result.updateCount == 1 else { throw .digest(.sessionStateViolation) }
        do { return try ArtifactID(digest: result.digest, byteCount: size) }
        catch { throw .artifactIdentity(error) }
    }
}
