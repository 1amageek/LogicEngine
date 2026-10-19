import LogicWordLoweringProbeSupport

@main struct ProbeEntry {
    static func main() {
        guard #available(macOS 26.0, *) else { preconditionFailure("Span probe requires macOS 26") }
        do { try WordLoweringContractProbe.exercise(); try AtomicAssignmentContractProbe.exercise(); try SourceLoweringContractProbe.exercise(); print("LOGIC_WORD_LOWERING_CONTRACT_OK") }
        catch { preconditionFailure("Word lowering probe failed") }
    }
}
