import Foundation
import CircuiteFoundation
import Testing
@testable import LogicEngine
@testable import LogicEngineCore
import LogicEngineRuntime

@Suite("LogicEngine capabilities")
struct LogicEngineCapabilitiesTests {
    @Test("native capabilities use the current schema")
    func nativeCapabilitiesUseCurrentSchema() {
        let capabilities = LogicEngineCapabilities.native

        #expect(capabilities.schemaVersion == SchemaVersion(major: 3, minor: 0, patch: 0))
        #expect(capabilities.lowering.typedWordLowering && capabilities.lowering.typedBitLowering)
        #expect(capabilities.lowering.binarySynthesisProfile)
        #expect(capabilities.synthesis.synthesisRequestMajorVersion == LogicSynthesisRequest.currentSchemaVersion.major)
        #expect(capabilities.simulation.requestSchemaMajor == LogicSimulationRequest.currentSchemaVersion.major)
        #expect(capabilities.equivalence.requestSchemaMajor == LogicEquivalenceRequest.currentSchemaVersion.major)
        #expect(capabilities.equivalence.independentRUPChecking && capabilities.equivalence.actualCellFunctions)
        #expect(capabilities.equivalence.checkedArtifactReload)
        #expect(capabilities.evidence.passiveReportValidation)
        #expect(capabilities.simulation.requestSchemaMajor == 4 && capabilities.simulation.fourState)
        #expect(capabilities.simulation.arbitraryWidth && capabilities.simulation.actualCellFunctions)
        #expect(capabilities.synthesis.equivalenceRequired)
        #expect(capabilities.synthesis.actualCellMapping && capabilities.synthesis.checkedArtifactReload)
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
