import Foundation
import CircuiteFoundation
import Testing
@testable import LogicEngine
@testable import LogicEngineCore

@Suite("LogicEngine capabilities")
struct LogicEngineCapabilitiesTests {
    @Test("native capabilities use the current schema")
    func nativeCapabilitiesUseCurrentSchema() {
        let capabilities = LogicEngineCapabilities.native

        #expect(capabilities.schemaVersion == LogicEngineCapabilities.currentSchemaVersion)
        #expect(capabilities.simulation.waveformFormats == [.vcd])
        #expect(capabilities.simulation.maximumArithmeticWidthBits == 64)
        #expect(capabilities.synthesis.equivalenceRequired)
        #expect(capabilities.synthesis.acceptanceState == .pendingEquivalence)
        #expect(capabilities.evidence.independentOracleCorrelation)
    }

    @Test("capabilities encode and decode through the public schema")
    func capabilitiesRoundTrip() throws {
        let encoded = try JSONEncoder().encode(LogicEngineCapabilities.native)
        let decoded = try JSONDecoder().decode(LogicEngineCapabilities.self, from: encoded)

        #expect(decoded == LogicEngineCapabilities.native)
    }

    @Test("capabilities reject an unsupported schema")
    func capabilitiesRejectUnsupportedSchema() throws {
        let unsupported = LogicEngineCapabilities(
            schemaVersion: SchemaVersion(major: 2, minor: 0, patch: 0),
            lowering: .native,
            simulation: .native,
            synthesis: .native,
            equivalence: .native,
            evidence: .native
        )
        let encoded = try JSONEncoder().encode(unsupported)

        #expect(throws: LogicExecutionError.self) {
            _ = try JSONDecoder().decode(LogicEngineCapabilities.self, from: encoded)
        }
    }
}
