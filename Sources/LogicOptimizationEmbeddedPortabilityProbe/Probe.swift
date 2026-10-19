import LogicOptimizationProbeSupport
@main struct Probe {
    static func main() throws { try run() }
    nonisolated static func run() throws {
        try LogicOptimizationContractProbe.exercise()
        print("LOGIC_STATE_OPTIMIZATION_OK")
        print("LOGIC_DECLARATION_SEMANTICS_OK")
        try TechnologyMappingContractProbe.exercise()
        print("LOGIC_TECHNOLOGY_MAPPING_OK")
    }
}
