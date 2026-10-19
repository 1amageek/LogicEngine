import LogicBitLoweringProbeSupport

@main struct ProbeEntry {
    static func main() {
        guard #available(macOS 26.0, *) else { preconditionFailure("Span probe requires macOS 26") }
        do { try BitLoweringContractProbe.exercise(); print("LOGIC_BIT_EXPANSION_CONTRACT_OK") }
        catch { preconditionFailure("Bit expansion probe failed") }
    }
}
