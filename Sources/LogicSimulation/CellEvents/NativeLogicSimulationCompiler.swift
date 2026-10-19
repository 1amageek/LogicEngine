import LogicIR
import LogicKernelCore

public struct NativeLogicSimulationCompiler: LogicSimulationCompiling {
    public init() {}
    public func compile(_ design: borrowing ElaboratedRTL, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicSimulationModel {
        let plan = try RTLSimulationAdmission.compile(design, context: &context)
        _ = try context.reserveStorage(byteCount: LogicSimulationModel.Storage.payloadByteCount)
        return .init(storage: .init(rtl: plan))
    }
    public func compile(_ design: borrowing MappedGateDesign, library: borrowing LogicTechnologyLibrary,
                        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSimulationModel {
        try design.validateLibrary(library, context: &context)
        var maximum = 0
        try library.withCells { cells throws(LogicKernelError) in
            for index in cells.indices {
                try context.charge(.workUnits)
                let cell = cells[index]
                try cell.withPins { pins throws(LogicKernelError) in
                    for pin in pins.indices {
                        try context.charge(.workUnits)
                        if let function = pins[pin].function { maximum = max(maximum, function.nodeCount) }
                    }
                }
                if let state = cell.state { maximum = max(maximum, state.nextState.nodeCount) }
            }
        }
        _ = try context.reserveStorage(byteCount: LogicSimulationModel.Storage.payloadByteCount)
        let storage = LogicSimulationModel.Storage(mapped: copy design, scratchCount: maximum)
        try storage.admit(context: &context)
        return .init(storage: storage)
    }
}
