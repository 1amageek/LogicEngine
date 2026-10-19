import LogicProofProbeSupport
@main struct Probe {
    static func main() throws { try run() }
    nonisolated static func run() throws { try LogicProofContractProbe.exercise(); print("LOGIC_RUP_CHECKING_OK") }
}
