import CircuiteFoundation
import LogicKernelCore
import LogicIR

public struct LogicMappingPolicy: Sendable {
    public let maximumCutInputs: Int
    public let maximumCellInputs: Int
    public let maximumCutsPerNode: Int
    public let realizationPolicy: MappedGateRealizationPolicy
    public let firstEntityID: DesignEntityID
    public init(maximumCutInputs: Int, maximumCellInputs: Int, maximumCutsPerNode: Int, firstEntityID: DesignEntityID,
                realizationPolicy: MappedGateRealizationPolicy = .standardNetlist)
        throws(LogicKernelError) {
        guard (1...6).contains(maximumCutInputs), (1...6).contains(maximumCellInputs), maximumCutsPerNode > 0 else {
            throw .invalidInput("Mapping requires one to six cut/cell search inputs and a positive cut count")
        }
        self.maximumCutInputs = maximumCutInputs; self.maximumCellInputs = maximumCellInputs
        self.maximumCutsPerNode = maximumCutsPerNode
        self.firstEntityID = firstEntityID; self.realizationPolicy = realizationPolicy
    }
}
