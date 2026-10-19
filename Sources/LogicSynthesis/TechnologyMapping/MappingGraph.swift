import LogicIR

internal struct MappingGraph {
    let nodes: [MappingLogicDraft]
    let ports: [BitLogicPort]
    let bits: [BitNodeIndex]
    let states: [BitLogicState]
    let order: [BitNodeIndex]
    var nodeCount: Int { nodes.count }
    var portCount: Int { ports.count }
    var portBitCount: Int { bits.count }
    var stateCount: Int { states.count }
    borrowing func withTables<Result, Failure: Error>(
        _ body: (borrowing Span<MappingLogicDraft>, borrowing Span<BitNodeIndex>, borrowing Span<BitLogicPort>,
                 borrowing Span<BitNodeIndex>, borrowing Span<BitLogicState>, borrowing Span<BitNodeIndex>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let n = nodes; let p = ports; let b = bits; let s = states; let o = order
        return try body(n.isEmpty ? Span() : n.span, Span(), p.isEmpty ? Span() : p.span,
            b.isEmpty ? Span() : b.span, s.isEmpty ? Span() : s.span, o.isEmpty ? Span() : o.span)
    }
}
