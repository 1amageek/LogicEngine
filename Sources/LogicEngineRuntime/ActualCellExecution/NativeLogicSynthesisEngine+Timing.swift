import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicKernelCore
import STAEngine
import TimingCore

extension NativeLogicSynthesisEngine {
    internal func analyzeTiming(_ request: LogicSynthesisRequest, mapped: MappedGateDesign,
                                operating: LogicCheckedOperatingConditions,
                                io: inout LogicRuntimeIO, context: inout LogicKernelContext) async throws -> LogicArtifactBinding? {
        guard let constraints = request.constraints.timing else { return nil }
        do {
            let designData = try Self.timingDesign(mapped, top: request.top)
            let design = try io.write(designData, name: "timing-design-v1.json", kind: .netlist, format: .json, request: request)
            let bound = try TimingArtifactBinding(reference: design.reference, availability: design.availability)
            let sta = try STARequest(runID: request.runID, design: bound, topDesignName: request.top,
                libraries: constraints.libraries, constraints: constraints.constraints,
                requestedModeIDs: constraints.modeIDs, requestedCornerIDs: constraints.cornerIDs,
                pdkManifest: constraints.pdkManifest, processID: constraints.processID, pdkVersion: constraints.pdkVersion,
                maxPaths: constraints.maximumPaths, characterizationPolicy: .requireObservedConditions,
                characterizationBindings: constraints.characterizationBindings,
                operatingSupplyAssumptions: try Self.supplyAssumptions(operating, context: &context))
            var snapshots: [ArtifactID: Data] = [design.id: designData]
            for input in sta.artifactBindings where input.id != design.id {
                snapshots[input.id] = try io.read(Self.logicBinding(input))
            }
            let engine: any STAExecuting = timing ?? NativeSTAEngine(reader: InMemoryTimingArtifactReader(artifacts: snapshots))
            let result = try await engine.execute(sta)
            try context.checkpoint()
            try Self.validateTiming(result, request: sta, constraints: constraints)
            return try io.write(LogicRuntimeIO.encode(result), name: "timing-result-v4.json", kind: .report, format: .json, request: request)
        } catch { throw LogicRuntimeError.timing(error) }
    }

    internal static func logicBinding(_ binding: TimingArtifactBinding) throws -> LogicArtifactBinding {
        let availability: ArtifactAvailability
        switch binding.availability {
        case .local(let id, let root, let path) where root.rawValue == TimingArtifactBinding.workspaceRootIdentifier:
            availability = .local(artifactID: id, rootID: try .init(rawValue: LogicArtifactBinding.workspaceRootIdentifier), relativePath: path)
        default: availability = binding.availability
        }
        return try .init(reference: binding.reference, availability: availability)
    }

    internal static func validateTiming(_ result: STAExecutionResult, request: STARequest,
                                        constraints: LogicSynthesisTimingConstraints) throws {
        guard result.status == .completed else {
            throw LogicRuntimeError.unsupported("STA did not complete: " + result.diagnostics.map(\.summary).joined(separator: "; "))
        }
        guard result.runID == request.runID,
              result.evidence.provenance.inputs == request.inputs,
              Set(result.payload.analyzedCorners) == Set(constraints.cornerIDs),
              Set(result.payload.analyzedModes) == Set(constraints.modeIDs),
              result.payload.processSelection != nil,
              let configuration = result.payload.effectiveConfiguration,
              configuration.characterizationPolicy == .requireObservedConditions,
              configuration.characterizationBindings == constraints.characterizationBindings,
              configuration.operatingSupplyAssumptions == request.operatingSupplyAssumptions.sorted(by: {
                  [$0.cornerID, $0.instance, $0.pin].lexicographicallyPrecedes([$1.cornerID, $1.instance, $1.pin])
              }),
              result.payload.provenance.designDigest == request.design.digest.hexadecimalValue,
              result.payload.provenance.constraintDigest == request.constraints.digest.hexadecimalValue,
              result.payload.provenance.pdkDigest == request.pdkManifest.digest.hexadecimalValue,
              result.payload.provenance.libraryDigests == request.libraries.map({ $0.artifact.digest.hexadecimalValue }) else {
            throw LogicRuntimeError.unsupported("STA did not establish the exact required design/corner/condition analysis")
        }
        for (required, actual, kind) in [(constraints.minimumSetupSlack, result.payload.worstSetupSlack, STAAnalysisKind.setup),
                                         (constraints.minimumHoldSlack, result.payload.worstHoldSlack, .hold)] {
            guard let required else { continue }
            guard !result.payload.unconstrainedEndpoints.contains(where: { $0.unconstrainedChecks?.contains(kind) ?? true }) else {
                throw LogicRuntimeError.unsupported("Required \(kind.rawValue) slack has unconstrained endpoints")
            }
            if let actual {
                guard actual.isFinite else { throw LogicRuntimeError.unsupported("Required \(kind.rawValue) slack is nonfinite") }
                guard actual >= required else { throw LogicRuntimeError.constraint("Candidate \(kind.rawValue) slack fails the required minimum") }
            } else {
                let relevant = result.payload.endpoints.filter { $0.staticChecks?.contains(kind) == true || $0.excludedChecks?.contains(kind) == true
                    || (kind == .setup ? $0.setupSlack != nil : $0.holdSlack != nil) }
                guard !relevant.isEmpty,
                      relevant.allSatisfy({ ($0.staticValue != nil && $0.staticChecks?.contains(kind) == true) || $0.excludedChecks?.contains(kind) == true }),
                      constraints.cornerIDs.allSatisfy({ corner in constraints.modeIDs.allSatisfy { mode in
                          relevant.contains { $0.cornerID == corner && $0.modeID == mode }
                      } }) else { throw LogicRuntimeError.unsupported("Required \(kind.rawValue) slack is unmeasured without complete static or excluded coverage") }
            }
        }
    }

    internal static func supplyAssumptions(_ operating: LogicCheckedOperatingConditions, context: inout LogicKernelContext) throws -> [STAOperatingSupplyAssumption] {
        var count = 0
        for record in operating.receipt.records {
            try context.charge(.workUnits)
            let next = count.addingReportingOverflow(record.normalPower.pgValues.count)
            guard !next.overflow else { throw LogicKernelError.invalidInput("Operating supply capacity overflow") }
            count = next.partialValue
        }
        let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(MemoryLayout<STAOperatingSupplyAssumption>.stride))
        guard !bytes.overflow else { throw LogicKernelError.invalidInput("Operating supply storage overflow") }
        _ = try context.reserveStorage(byteCount: bytes.partialValue)
        var result: [STAOperatingSupplyAssumption] = []
        result.reserveCapacity(count)
        for record in operating.receipt.records {
            guard let corner = record.cornerID else { throw LogicOperatingConditionError.invalidInput("Source-only conditions cannot enter STA") }
            for pg in record.normalPower.pgValues {
                try context.charge(.workUnits, amount: UInt64(pg.condition.pin.utf8.count + pg.condition.sourcePGType.utf8.count) + 1)
                result.append(try .init(instance: record.interchangeName, cell: record.cellName, cornerID: corner,
                    library: record.library, pin: pg.condition.pin, sourcePGType: pg.condition.sourcePGType,
                    value: pg.condition.value ? .one : .zero))
            }
        }
        return result
    }

    internal static func timingDesign(_ mapped: MappedGateDesign, top: String) throws -> Data {
        try mapped.withTables { nets, instances, pins, ports, bits, _ in
            var names = nets.indices.map { "n\($0)" }; var assigned = Set<Int>()
            for p in ports.indices {
                for b in 0..<ports[p].bits.count {
                    let n = bits[ports[p].bits.lowerBound + b].rawValue
                    if assigned.insert(n).inserted { names[n] = "p\(p)_\(b)" }
                }
            }
            var timingPorts: [TimingDesign.Port] = []
            for p in ports.indices {
                for b in 0..<ports[p].bits.count {
                    let n = bits[ports[p].bits.lowerBound + b].rawValue
                    let name = "p\(p)_\(b)"
                    timingPorts.append(.init(name: name, direction: ports[p].direction == .input ? .input : .output,
                        net: names[n] == name ? nil : names[n]))
                }
            }
            var timingNets: [TimingDesign.Net] = []
            for n in nets.indices {
                let constant: TimingDesign.Constant?
                if case .constant(let value) = nets[n].driver { constant = value ? .one : .zero }
                else { constant = nil }
                timingNets.append(.init(name: names[n], constant: constant))
            }
            var timingInstances: [TimingDesign.Instance] = []
            for i in instances.indices {
                let cell = try mapped.library.cell(at: instances[i].cell); var connections: [String: String] = [:]
                for p in 0..<cell.pinCount { connections[try cell.pin(at: .init(p)).name] = names[pins[instances[i].pins.lowerBound + p].rawValue] }
                timingInstances.append(.init(name: "i\(i)", cell: cell.name, connections: connections))
            }
            return try LogicRuntimeIO.encode(TimingDesign(topDesignName: top, ports: timingPorts,
                instances: timingInstances, nets: timingNets))
        }
    }
}
