internal struct MappingSolution {
    enum Implementation { case terminal, constant(Bool), alias(Int, inverted: Bool), cell(MappingMatch) }
    let cut: MappingCut
    let implementation: Implementation
    let area: Double
    let depth: Int
}
