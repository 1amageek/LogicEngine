import LogicSimulationProbeSupport
@main struct Probe {
    static func main() throws { try run() }
    nonisolated static func run() throws { try LogicSimulationProbeFixtures.exercise(); try RTLSimulationContractProbe.exercise(); print("LOGIC_CELL_EVENTS_OK"); print("LOGIC_RTL_EVENTS_OK") }
}
