import CircuiteFoundation
import LogicIR
import LogicKernelCore

internal struct MappingInstanceDraft {
    let id: DesignEntityID
    let cell: LogicCellIndex
    var pins: [MappedNetIndex]
    let stateID: DesignEntityID?
    let initial: Bool?
    let origin: LogicKernelSourceRange?
}
