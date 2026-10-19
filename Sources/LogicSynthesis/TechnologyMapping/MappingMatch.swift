import LogicIR

internal struct MappingMatch {
    let cell: LogicCellIndex
    let output: LogicCellPinIndex
    // Input slots encode ties or positive/inverted leaves; inputless tie matches retain output values as zero/one.
    let bindings: [Int]
    let invertedOutput: Bool
    let area: Double
    let depth: Int
}
