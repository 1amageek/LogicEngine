import CircuiteFoundation
import LogicKernelCore
import TimingCore

public enum LogicLibraryCompilationError: Error, Sendable {
    case kernel(LogicKernelError)
    case normalPower(LibertyNormalPowerError)
    case digest(ContentDigestError)
    case artifactIdentity(ArtifactIDError)
    case sourceIdentityMismatch(expected: ArtifactID, actual: ArtifactID)
    case sourceByteCountMismatch(expected: UInt64, actual: UInt64)
    indirect case cleanup(primary: LogicLibraryCompilationError, cause: LogicKernelError)
}
