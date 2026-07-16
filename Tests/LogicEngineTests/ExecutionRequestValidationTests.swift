import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicLowering
import LogicSimulation
import LogicSynthesis
import Testing

@Suite("LogicEngine execution request validation")
struct ExecutionRequestValidationTests {
    @Test
    func loweringRejectsBlankRunID() throws {
        let request = LogicLoweringRequest(
            runID: " \n",
            design: LogicDesignArtifact(
                artifact: try artifact(id: "design"),
                topDesignName: "top"
            )
        )

        #expect(throws: LogicExecutionContractError.self) {
            try request.validate()
        }
    }

    @Test
    func simulationRejectsStimulusMissingFromInputs() throws {
        let design = try artifact(id: "design")
        let stimulus = try artifact(id: "stimulus")
        let request = LogicSimulationRequest(
            runID: "simulation",
            design: LogicDesignArtifact(artifact: design, topDesignName: "top"),
            stimulus: stimulus
        )
        let encodedRequest = try JSONEncoder().encode(request)
        var object = try #require(
            JSONSerialization.jsonObject(with: encodedRequest) as? [String: Any]
        )
        object["inputs"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([design])
        )
        let invalidRequest = try JSONDecoder().decode(
            LogicSimulationRequest.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(throws: LogicExecutionContractError.self) {
            try invalidRequest.validate()
        }
    }

    @Test
    func boundedEquivalenceRejectsDuplicateOutputSignals() throws {
        let reference = LogicDesignArtifact(
            artifact: try artifact(id: "reference"),
            topDesignName: "top"
        )
        let implementation = LogicDesignArtifact(
            artifact: try artifact(id: "implementation"),
            topDesignName: "top"
        )
        let request = LogicBoundedTemporalEquivalenceRequest(
            runID: "equivalence",
            referenceDesign: reference,
            implementationDesign: implementation,
            stimulus: try artifact(id: "stimulus"),
            outputSignals: ["out", "out"],
            sampleLimit: 1
        )

        #expect(throws: LogicExecutionContractError.self) {
            try request.validate()
        }
    }

    @Test
    func requestInitializersCanonicalizeArtifactInputs() throws {
        let design = try artifact(id: "design")
        let stimulus = try artifact(id: "stimulus")
        let request = LogicSimulationRequest(
            runID: "simulation",
            inputs: [design, stimulus, design],
            design: LogicDesignArtifact(artifact: design, topDesignName: "top"),
            stimulus: stimulus
        )

        #expect(request.inputs == [design, stimulus])
    }

    private func artifact(id: String) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/\(id).json"),
                role: .input,
                kind: .netlist,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "a", count: 64)
            ),
            byteCount: 1
        )
    }
}
