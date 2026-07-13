import Testing
@testable import LogicSimulation
@testable import LogicSynthesis
@testable import LogicEngine

@Suite("LogicEngine contract")
struct ContractTests {
    @Test("contract version starts at one")
    func contractVersion() {
        #expect(LogicEngineAPI.contractVersion == 1)
    }
}
