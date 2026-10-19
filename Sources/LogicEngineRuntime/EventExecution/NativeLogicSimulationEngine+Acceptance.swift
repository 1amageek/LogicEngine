import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicKernelCore

extension NativeLogicSimulationEngine {
    internal static func operationalInputs(_ request: LogicSimulationRequest, io: LogicRuntimeIO) throws
        -> (inputs: [ArtifactReference], bindings: [LogicArtifactBinding]) {
        let readBindings = io.verifiedReadBindings ?? []
        let references = Set(request.inputs).union(readBindings.map(\.reference))
        let encoded = try references.map { (reference: $0, bytes: try LogicRuntimeIO.encode($0)) }
        let inputs = encoded.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }.map(\.reference)
        let encodedBindings = try readBindings.map { (binding: $0, bytes: try LogicRuntimeIO.encode($0)) }
            .sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }
        let bindings = try inputs.map { reference in
            guard let binding = encodedBindings.first(where: { $0.binding.reference == reference })?.binding else {
                throw LogicKernelError.invalidInput("Simulation operational input was not independently read")
            }
            return binding
        }
        return (inputs, bindings)
    }

    internal static func specification(_ request: LogicSimulationRequest, io: inout LogicRuntimeIO,
                                       context: inout LogicKernelContext) throws -> LogicSimulationSpecification? {
        guard let binding = request.specification else { return nil }
        let specification = try JSONDecoder().decode(LogicSimulationSpecification.self, from: io.read(binding))
        try specification.validate(for: request, context: &context)
        return specification
    }

    internal static func assess(_ observations: [LogicSimulationObservationRecord],
                                specification: LogicSimulationSpecification?,
                                context: inout LogicKernelContext) throws -> LogicSimulationAssessment {
        guard let specification else { return .init(status: .unassessed, checkedAssertionCount: 0, violations: []) }
        var violations: [LogicSimulationAssessment.Violation] = []
        for assertion in specification.assertions {
            try context.charge(.workUnits)
            let observation = assertion.observationIndex < observations.count ? observations[assertion.observationIndex] : nil
            try context.charge(.workUnits, amount: UInt64(observation?.outputs.count ?? 0))
            let output = observation?.outputs.first { $0.portIndex == assertion.portIndex }
            try context.charge(.workUnits, amount: UInt64(assertion.expectedValue.utf8.count + (output?.value.utf8.count ?? 0)))
            let expected = assertion.expectedValue.lowercased()
            let reason: LogicSimulationAssessment.Violation.Reason?
            if observation == nil { reason = .missingObservation }
            else if observation?.time != assertion.time { reason = .timeMismatch }
            else if output == nil { reason = .missingOutput }
            else if output?.value != expected { reason = .valueMismatch }
            else { reason = nil }
            if let reason {
                try context.charge(.outputBytes, amount: UInt64(expected.utf8.count + (output?.value.utf8.count ?? 0)))
                violations.append(.init(assertionID: assertion.id, reason: reason,
                    observationIndex: assertion.observationIndex, expectedTime: assertion.time, actualTime: observation?.time,
                    portIndex: assertion.portIndex, expectedValue: expected, actualValue: output?.value))
            }
        }
        return .init(status: violations.isEmpty ? .passed : .failed,
                     checkedAssertionCount: specification.assertions.count, violations: violations)
    }

    public func load(_ acceptance: LogicArtifactBinding, expectedRequest: LogicSimulationRequest,
                     limits: LogicRuntimeLimits) async throws -> LogicSimulationAcceptance {
        try expectedRequest.validate()
        let control = LogicRuntimeControl(timeout: limits.timeoutNanoseconds)
        var io = LogicRuntimeIO(store: artifactStore, limits: limits, control: control)
        var context = LogicKernelContext(limits: try limits.kernelLimits(), control: control)
        let saved = try JSONDecoder().decode(LogicSimulationAcceptance.self, from: io.read(acceptance))
        guard saved.schemaVersion == 2, saved.algorithm == LogicSimulationAcceptance.algorithmIdentity,
              saved.producer.kind == .engine, saved.producer.identifier == "logic.four-state.simulation", saved.producer.version == "1.2.0",
              saved.producer.build != nil else { throw LogicKernelError.invalidInput("Unsupported simulation acceptance producer or algorithm") }
        let request = try JSONDecoder().decode(LogicSimulationRequest.self, from: io.read(saved.request))
        try request.validate()
        guard request == expectedRequest, saved.specification == request.specification else {
            throw LogicKernelError.invalidInput("Simulation acceptance differs from current request or specification")
        }
        let observations = try JSONDecoder().decode([LogicSimulationObservationRecord].self, from: io.read(saved.observations))
        io.verifiedReadBindings = []
        let specification = try Self.specification(request, io: &io, context: &context)
        let replayed = try await evaluate(request, io: &io, context: &context)
        guard observations == replayed else { throw LogicKernelError.invalidInput("Saved simulation observations differ from exact-input replay") }
        let assessment = try Self.assess(replayed, specification: specification, context: &context)
        let operational = try Self.operationalInputs(request, io: io)
        guard saved.operationalInputs == operational.inputs, saved.operationalInputBindings == operational.bindings else {
            throw LogicKernelError.invalidInput("Saved simulation operational inputs differ from exact verified replay")
        }
        guard saved.assessment == assessment else { throw LogicKernelError.invalidInput("Saved simulation assessment differs from assertion replay") }
        return saved
    }
}
