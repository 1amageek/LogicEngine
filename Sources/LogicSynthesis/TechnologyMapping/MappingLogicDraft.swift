import CircuiteFoundation
import LogicIR
import LogicKernelCore

internal struct MappingLogicDraft {
    let id: DesignEntityID
    let operation: BitOperation
    let inputs: [BitNodeIndex]
    let origin: LogicKernelSourceRange?
}
