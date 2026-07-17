import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import LogicSynthesis
import Testing

@Suite("LogicEngine execution request validation")
struct ExecutionRequestValidationTests {
    @Test
    func loweringRejectsBlankRunID() throws {
        let design = try artifact(id: "design")
        let request = LogicLoweringRequest(
            runID: " \n",
            design: LogicDesignReference(
                artifact: design,
                topDesignName: "top",
                designRevision: design.digest
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
            design: LogicDesignReference(
                artifact: design,
                topDesignName: "top",
                designRevision: design.digest
            ),
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
        let referenceArtifact = try artifact(id: "reference")
        let implementationArtifact = try artifact(id: "implementation")
        let reference = LogicDesignReference(
            artifact: referenceArtifact,
            topDesignName: "top",
            designRevision: referenceArtifact.digest
        )
        let implementation = LogicDesignReference(
            artifact: implementationArtifact,
            topDesignName: "top",
            designRevision: implementationArtifact.digest
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
            design: LogicDesignReference(
                artifact: design,
                topDesignName: "top",
                designRevision: design.digest
            ),
            stimulus: stimulus
        )

        #expect(request.inputs == [design, stimulus])
    }

    @Test
    func loweringRejectsMalformedCanonicalDesignDigest() throws {
        let design = try artifact(id: "design")
        let request = LogicLoweringRequest(
            runID: "lowering",
            design: LogicDesignReference(
                artifact: design,
                topDesignName: "top",
                designDigest: "not-a-sha256-digest"
            )
        )

        #expect(throws: LogicExecutionContractError.self) {
            try request.validate()
        }
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
