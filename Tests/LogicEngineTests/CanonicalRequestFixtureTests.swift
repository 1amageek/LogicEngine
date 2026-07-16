import Foundation
import LogicLowering
import LogicSimulation
import LogicSynthesis
import Testing

@Suite("Canonical execution request fixtures")
struct CanonicalRequestFixtureTests {
    @Test
    func fixturesDecodeAndValidate() throws {
        let lowering: LogicLoweringRequest = try decode("logic-lowering-request")
        let simulation: LogicSimulationRequest = try decode("logic-simulation-request")
        let synthesis: LogicSynthesisRequest = try decode("logic-synthesis-request")
        let bounded: LogicBoundedTemporalEquivalenceRequest = try decode(
            "logic-bounded-equivalence-request"
        )
        let unbounded: LogicUnboundedTemporalEquivalenceRequest = try decode(
            "logic-unbounded-equivalence-request"
        )

        try lowering.validate()
        try simulation.validate()
        try synthesis.validate()
        try bounded.validate()
        try unbounded.validate()
    }

    private func decode<Value: Decodable>(_ name: String) throws -> Value {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw FixtureError.missing(name)
        }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }
}

private enum FixtureError: Error {
    case missing(String)
}
