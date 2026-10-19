import CircuiteFoundation
import LogicKernelCore
import TimingCore

public protocol LogicTechnologyLibraryCompiling: Sendable {
    func compile(_ source: borrowing OwnedLibertySource, identity: ArtifactID,
                 options: borrowing LogicLibraryCompilationOptions, context: inout LogicKernelContext)
        throws(LogicLibraryCompilationError) -> LogicLibraryCompilation
}
