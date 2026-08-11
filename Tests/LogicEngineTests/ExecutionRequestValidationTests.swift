import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import LogicSynthesis
import Testing
import CircuiteFoundationFoundation

@Suite("LogicEngine execution request validation")
struct ExecutionRequestValidationTests {
    @Test
    func loweringRejectsBlankRunID() throws {
        let design = try artifact(id: "design")
        let request = LogicLoweringRequest(
            runID: " \n",
            inputBindings: [design],
            design: LogicDesignReference(
                artifact: design.reference,
                topDesignName: "top",
                canonicalDesignDigest: design.digest
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
            inputBindings: [design, stimulus],
            design: LogicDesignReference(
                artifact: design.reference,
                topDesignName: "top",
                canonicalDesignDigest: design.digest
            ),
            stimulus: stimulus
        )
        let encodedRequest = try JSONEncoder().encode(request)
        var object = try #require(
            JSONSerialization.jsonObject(with: encodedRequest) as? [String: Any]
        )
        object["inputs"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([design.reference])
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
            artifact: referenceArtifact.reference,
            topDesignName: "top",
            canonicalDesignDigest: referenceArtifact.digest
        )
        let implementation = LogicDesignReference(
            artifact: implementationArtifact.reference,
            topDesignName: "top",
            canonicalDesignDigest: implementationArtifact.digest
        )
        let request = LogicBoundedTemporalEquivalenceRequest(
            runID: "equivalence",
            inputBindings: [referenceArtifact, implementationArtifact],
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
            inputBindings: [design, stimulus, design],
            design: LogicDesignReference(
                artifact: design.reference,
                topDesignName: "top",
                canonicalDesignDigest: design.digest
            ),
            stimulus: stimulus
        )

        #expect(request.inputs == [design.reference, stimulus.reference])
    }

    @Test
    func loweringRejectsMalformedCanonicalDesignDigest() throws {
        let design = try artifact(id: "design")
        let request = LogicLoweringRequest(
            runID: "lowering",
            inputBindings: [design],
            design: LogicDesignReference(
                artifact: design.reference,
                topDesignName: "top",
                designDigest: "not-a-sha256-digest"
            )
        )

        #expect(throws: LogicExecutionContractError.self) {
            try request.validate()
        }
    }

    private func artifact(id: String) throws -> LogicArtifactBinding {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "inputs/\(id).json"),
            role: .input,
            kind: .netlist,
            format: .json
        )
        let reference = try ArtifactReference(
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "a", count: 64)
            ),
            byteCount: 1,
            descriptor: locator.descriptor
        )
        return try LogicArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(
                    rawValue: LogicArtifactBinding.workspaceRootIdentifier
                ),
                relativePath: try ArtifactRelativePath(
                    segments: ["inputs", "\(id).json"]
                )
            ),
        )
    }
}
