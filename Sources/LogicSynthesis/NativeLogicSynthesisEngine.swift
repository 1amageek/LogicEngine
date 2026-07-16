import Foundation
import LogicEngineCore
import LogicIR
import PDKCore
import PowerIntent
import TimingCore
import CircuiteFoundation

public struct NativeLogicSynthesisEngine: LogicSynthesisExecuting {
    public let artifactStore: any LogicArtifactStoring
    public let implementationVersion: String

    public init(
        artifactStore: any LogicArtifactStoring = FileSystemLogicArtifactStore(),
        implementationVersion: String = "1"
    ) {
        self.artifactStore = artifactStore
        self.implementationVersion = implementationVersion
    }

    public func execute(
        _ request: LogicSynthesisRequest
    ) async throws -> LogicSynthesisResult {
        let startedAt = Date()
        do {
            try validate(request)
            try checkCancellation()
            for input in request.inputs {
                _ = try artifactStore.read(input)
            }

            let designData = try artifactStore.read(request.design.artifact)
            let designDigest = request.design.designRevision?.hexadecimalValue
                ?? request.design.artifact.sha256
            guard request.design.designRevision == nil
                || request.design.designRevision?.hexadecimalValue == designDigest else {
                throw LogicExecutionError.artifactDigestMismatch(request.design.artifact.path)
            }
            let design = try decodeDesign(designData)
            guard design.topDesignName == request.design.topDesignName else {
                throw LogicExecutionError.invalidDesign(
                    "request top design \(request.design.topDesignName) does not match artifact \(design.topDesignName)"
                )
            }
            try design.validateNativeExecutionTopology()

            let libraryResult = try loadLibraries(request.libraries)
            let constraintsResult = try loadConstraints(request.constraints.artifact)
            let pdkDigest = try loadAndValidatePDK(request.pdk)
            if let powerIntent = request.powerIntent {
                guard request.inputs.contains(powerIntent.artifact) else {
                    throw LogicExecutionError.missingPrerequisite(
                        "power intent artifact is missing from the input set"
                    )
                }
                let powerIntentData = try artifactStore.read(powerIntent.artifact)
                let powerIntentDigest = try digestHex(powerIntentData)
                guard powerIntent.designDigest.isEmpty || powerIntent.designDigest == designDigest else {
                    throw LogicExecutionError.artifactDigestMismatch(
                        powerIntent.artifact.locator.location.value
                    )
                }
                guard !powerIntentData.isEmpty else {
                    throw LogicExecutionError.invalidArtifact("power intent artifact is empty")
                }
                _ = powerIntentDigest
            }
            try checkCancellation()

            let loweredNodeCount = design.nodes.count
            let optimization = try optimize(design)
            let mapped = try map(
                design: optimization.design,
                library: libraryResult.library,
                constraints: constraintsResult.constraints
            )
            try checkCancellation()

            let outputDesignData = try encode(mapped.design)
            let outputDesignDigest = try digestHex(outputDesignData)
            let mappedReference = try artifactStore.write(
                outputDesignData,
                fileName: "mapped-design.json",
                outputDirectory: request.artifactDirectory,
                runID: request.runID,
                artifactID: "mapped-design",
                kind: .netlist,
                format: .json
            )
            let provenance = LogicSynthesisProvenance(
                runID: request.runID,
                inputDesignDigest: designDigest,
                outputDesignDigest: outputDesignDigest,
                libraryDigests: libraryResult.digests,
                pdkDigest: pdkDigest,
                constraintsDigest: constraintsResult.digest,
                transformations: optimization.transformations
            )
            let provenanceData = try encode(provenance)
            let provenanceReference = try artifactStore.write(
                provenanceData,
                fileName: "synthesis-provenance.json",
                outputDirectory: request.artifactDirectory,
                runID: request.runID,
                artifactID: "logic-synthesis-provenance",
                kind: .report,
                format: .json
            )
            let mappedDesignArtifact = LogicDesignArtifact(
                artifact: mappedReference,
                topDesignName: mapped.design.topDesignName,
                designRevision: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: outputDesignDigest
                )
            )
            let mappedDesign = LogicDesignReference(
                artifact: mappedReference,
                topDesignName: mapped.design.topDesignName,
                designDigest: outputDesignDigest,
                provenance: LogicDesignProvenance(
                    sourceDesignDigest: designDigest,
                    inputDesignDigest: designDigest,
                    transformationID: "native-synthesis",
                    producerID: "LogicSynthesis",
                    producerVersion: implementationVersion,
                    runID: request.runID
                )
            )
            let equivalenceRequest = LogicSynthesisEquivalenceRequest(
                runID: request.runID,
                topDesignName: mapped.design.topDesignName,
                sourceDesign: LogicDesignReference(
                    artifact: request.design.artifact,
                    topDesignName: request.design.topDesignName,
                    designDigest: designDigest
                ),
                mappedDesign: mappedDesign,
                synthesisProvenance: provenanceReference
            )
            try equivalenceRequest.validate()
            let equivalenceRequestData = try encode(equivalenceRequest)
            let equivalenceRequestReference = try artifactStore.write(
                equivalenceRequestData,
                fileName: "logic-equivalence-request.json",
                outputDirectory: request.artifactDirectory,
                runID: request.runID,
                artifactID: "logic-equivalence-request",
                kind: .report,
                format: .json
            )
            var diagnostics: [DesignDiagnostic] = [
                DesignDiagnostic(
                    severity: .information,
                    code: "LOGIC_SYNTHESIS_COMPLETED",
                    message: "Lowered \(loweredNodeCount) node(s), optimized to \(optimization.design.nodes.count), and mapped \(mapped.cellCount) cell(s)."
                ),
                DesignDiagnostic(
                    severity: .warning,
                    code: "LOGIC_EQUIVALENCE_REQUIRED",
                    message: "The mapped design remains pending equivalence acceptance; a typed equivalence request was emitted.",
                    suggestedActions: ["run_formal_equivalence", "review_synthesis_provenance", "retain_equivalence_request"]
                ),
            ]
            if let targetClockPeriod = constraintsResult.constraints.targetClockPeriod {
                diagnostics.append(DesignDiagnostic(
                    severity: .information,
                    code: "LOGIC_TARGET_CLOCK_PERIOD",
                    message: "Synthesis used target clock period \(targetClockPeriod)."
                ))
            }
            let payload = LogicSynthesisPayload(
                mappedDesign: mappedDesignArtifact,
                mappedCellCount: mapped.cellCount,
                loweredNodeCount: loweredNodeCount,
                optimizedNodeCount: optimization.design.nodes.count,
                totalArea: mapped.totalArea,
                totalPower: mapped.totalPower,
                provenance: provenanceReference,
                equivalenceRequest: equivalenceRequestReference,
                equivalenceRequired: true,
                acceptanceState: .pendingEquivalence
            )
            return LogicSynthesisResult(
                schemaVersion: LogicSynthesisRequest.currentSchemaVersion,
                runID: request.runID,
                status: .completed,
                diagnostics: diagnostics,
                artifacts: [mappedReference, provenanceReference, equivalenceRequestReference],
                provenance: try ExecutionProvenance(
                    producer: ProducerIdentity(
                        kind: .engine,
                        identifier: "LogicSynthesis",
                        version: implementationVersion,
                        build: "native-lowering-optimization-mapping"
                    ),
                    inputs: request.inputs,
                    invocation: ExecutionInvocation.inProcess(
                        entryPoint: "NativeLogicSynthesisEngine.execute"
                    ),
                    randomSeed: nil,
                    startedAt: startedAt,
                    completedAt: Date()
                ),
                payload: payload
            )
        } catch let error as LogicExecutionError {
            return try failureEnvelope(request: request, error: error, startedAt: startedAt)
        } catch {
            throw error
        }
    }

    private func validate(_ request: LogicSynthesisRequest) throws {
        try request.validate()
    }

    private func decodeDesign(_ data: Data) throws -> LogicDesignDocument {
        do {
            let design = try JSONDecoder().decode(LogicDesignDocument.self, from: data)
            try design.validate()
            return design
        } catch let error as LogicExecutionError {
            throw error
        } catch {
            throw LogicExecutionError.invalidArtifact(
                "design JSON could not be decoded: \(String(reflecting: error))"
            )
        }
    }

    private func loadLibraries(_ references: [TimingLibraryReference]) throws -> LibraryResult {
        var cells: [LogicCell] = []
        var digests: [String] = []
        for reference in references {
            let data = try artifactStore.read(reference.artifact)
            let digest = try digestHex(data)
            digests.append(digest)
            let library = try decodeLibrary(data: data, path: reference.artifact.path)
            try library.validate()
            cells.append(contentsOf: library.cells)
        }
        return LibraryResult(
            library: LogicCellLibraryDocument(libraryName: "combined", cells: cells),
            digests: digests
        )
    }

    private func decodeLibrary(data: Data, path: String) throws -> LogicCellLibraryDocument {
        do {
            return try JSONDecoder().decode(LogicCellLibraryDocument.self, from: data)
        } catch {
            guard let text = String(data: data, encoding: .utf8) else {
                throw LogicExecutionError.invalidArtifact("timing library \(path) is neither JSON nor UTF-8 Liberty text")
            }
            return try parseLiberty(text: text, path: path)
        }
    }

    private func parseLiberty(text: String, path: String) throws -> LogicCellLibraryDocument {
        var cells: [LogicCell] = []
        var currentName: String?
        var currentKind: LogicNodeKind?
        var currentInputCount = 2
        var currentArea = 0.0
        var currentPower = 0.0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("cell (") {
                if let currentName, let currentKind {
                    cells.append(LogicCell(
                        name: currentName,
                        kind: currentKind,
                        inputCount: currentInputCount,
                        area: currentArea,
                        power: currentPower
                    ))
                }
                currentName = parseParenthesizedName(line)
                currentKind = nil
                currentInputCount = 2
                currentArea = 0
                currentPower = 0
            } else if line.contains("function") {
                currentKind = inferKind(from: line)
                currentInputCount = inferInputCount(from: line)
            } else if line.hasPrefix("area :") {
                currentArea = parseNumber(line, field: "area", path: path)
            } else if line.contains("power") && line.contains(":") {
                currentPower = parseNumber(line, field: "power", path: path)
            }
        }
        if let currentName, let currentKind {
            cells.append(LogicCell(
                name: currentName,
                kind: currentKind,
                inputCount: currentInputCount,
                area: currentArea,
                power: currentPower
            ))
        }
        guard !cells.isEmpty else {
            throw LogicExecutionError.invalidArtifact("timing library \(path) contains no supported cells")
        }
        return LogicCellLibraryDocument(libraryName: path, cells: cells)
    }

    private func loadConstraints(_ reference: ArtifactReference) throws -> ConstraintResult {
        let data = try artifactStore.read(reference)
        let digest = try digestHex(data)
        do {
            let constraints = try JSONDecoder().decode(LogicConstraintDocument.self, from: data)
            try constraints.validate()
            return ConstraintResult(constraints: constraints, digest: digest)
        } catch let error as LogicExecutionError where !isJSONDecodeError(error) {
            throw error
        } catch {
            guard reference.format == .sdc || reference.format == .text || reference.format == .unknown else {
                throw LogicExecutionError.invalidArtifact(
                    "constraint JSON could not be decoded: \(error.localizedDescription)"
                )
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw LogicExecutionError.invalidArtifact("constraint artifact is not UTF-8")
            }
            let constraints = try parseSDC(text)
            try constraints.validate()
            return ConstraintResult(constraints: constraints, digest: digest)
        }
    }

    private func parseSDC(_ text: String) throws -> LogicConstraintDocument {
        var maximumArea: Double?
        var maximumPower: Double?
        var maximumLogicDepth: Int?
        var targetClockPeriod: Double?
        for rawLine in text.split(separator: "\n") {
            let tokens = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard !tokens.isEmpty else { continue }
            if tokens[0] == "set_max_area" {
                maximumArea = try parseDirectiveDouble(tokens, name: "set_max_area")
            } else if tokens[0] == "set_max_power" {
                maximumPower = try parseDirectiveDouble(tokens, name: "set_max_power")
            } else if tokens[0] == "set_max_logic_depth" {
                let value = try parseDirectiveDouble(tokens, name: "set_max_logic_depth")
                maximumLogicDepth = Int(value)
            } else if tokens.contains("-period"), let index = tokens.firstIndex(of: "-period"), index + 1 < tokens.count {
                guard let value = Double(tokens[index + 1]) else {
                    throw LogicExecutionError.invalidArtifact("invalid create_clock period")
                }
                targetClockPeriod = value
            }
        }
        return LogicConstraintDocument(
            maximumArea: maximumArea,
            maximumPower: maximumPower,
            maximumLogicDepth: maximumLogicDepth,
            targetClockPeriod: targetClockPeriod
        )
    }

    private func loadAndValidatePDK(_ reference: PDKReference) throws -> String {
        let data = try artifactStore.read(reference.manifest)
        guard !data.isEmpty else {
            throw LogicExecutionError.missingPrerequisite("PDK manifest is empty")
        }
        let actualDigest = try digestHex(data)
        guard reference.digest == actualDigest else {
            throw LogicExecutionError.artifactDigestMismatch(reference.manifest.path)
        }
        return actualDigest
    }

    private func optimize(_ design: LogicDesignDocument) throws -> OptimizationResult {
        var optimized = design
        var transformations: [LogicTransformationRecord] = []
        let portNames = Set(design.ports.map(\.name))
        var removedNodeIDs: [String] = []
        for node in design.nodes where node.kind == .buffer && node.inputs.count == 1 && node.outputs.count == 1 {
            let source = node.inputs[0]
            let destination = node.outputs[0]
            guard !portNames.contains(destination) else { continue }
            for index in optimized.nodes.indices {
                optimized.nodes[index].inputs = optimized.nodes[index].inputs.map { $0 == destination ? source : $0 }
            }
            removedNodeIDs.append(node.id)
            transformations.append(LogicTransformationRecord(
                transformationID: "buffer-elimination-\(node.id)",
                kind: "buffer_elimination",
                sourceNodeIDs: [node.id],
                resultNodeIDs: [],
                rationale: "Removed a non-observable buffer and rewired its consumers to the source signal."
            ))
        }
        if !removedNodeIDs.isEmpty {
            optimized.nodes.removeAll { removedNodeIDs.contains($0.id) }
        }
        optimized.metadata["logicEngine.optimization"] = "deterministic-buffer-elimination"
        try optimized.validate()
        return OptimizationResult(
            design: optimized,
            transformations: transformations
        )
    }

    private func map(
        design: LogicDesignDocument,
        library: LogicCellLibraryDocument,
        constraints: LogicConstraintDocument
    ) throws -> MappingResult {
        var mappedDesign = design
        var totalArea = 0.0
        var totalPower = 0.0
        for index in mappedDesign.nodes.indices {
            let node = mappedDesign.nodes[index]
            guard let cell = library.cell(for: node.kind, inputCount: node.inputs.count) else {
                throw LogicExecutionError.missingPrerequisite(
                    "cell for \(node.kind.rawValue) with \(node.inputs.count) input(s)"
                )
            }
            mappedDesign.nodes[index].parameters["mappedCell"] = cell.name
            totalArea += cell.area
            totalPower += cell.power
        }
        let depth = logicDepth(of: mappedDesign)
        if let maximumLogicDepth = constraints.maximumLogicDepth, depth > maximumLogicDepth {
            throw LogicExecutionError.constraintViolation(
                "logic depth \(depth) exceeds maximum \(maximumLogicDepth)"
            )
        }
        if let maximumArea = constraints.maximumArea, totalArea > maximumArea {
            throw LogicExecutionError.constraintViolation(
                "area \(totalArea) exceeds maximum \(maximumArea)"
            )
        }
        if let maximumPower = constraints.maximumPower, totalPower > maximumPower {
            throw LogicExecutionError.constraintViolation(
                "power \(totalPower) exceeds maximum \(maximumPower)"
            )
        }
        mappedDesign.metadata["logicEngine.mapping"] = "declared-library-cell"
        try mappedDesign.validate()
        return MappingResult(
            design: mappedDesign,
            cellCount: mappedDesign.nodes.count,
            totalArea: totalArea,
            totalPower: totalPower
        )
    }

    private func logicDepth(of design: LogicDesignDocument) -> Int {
        var signalDepth: [String: Int] = [:]
        var maximumDepth = 0
        for node in design.nodes.sorted(by: { $0.id < $1.id }) {
            let inputDepth = node.inputs.map { signalDepth[$0] ?? 0 }.max() ?? 0
            let depth = inputDepth + 1
            maximumDepth = max(maximumDepth, depth)
            for output in node.outputs {
                signalDepth[output] = max(signalDepth[output] ?? 0, depth)
            }
        }
        return maximumDepth
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(value)
        } catch {
            throw LogicExecutionError.artifactWriteFailed("JSON encoding failed: \(error.localizedDescription)")
        }
    }

    private func digestHex(_ data: Data) throws -> String {
        try SHA256ContentDigester()
            .digest(data: data, using: .sha256)
            .hexadecimalValue
    }

    private func failureEnvelope(
        request: LogicSynthesisRequest,
        error: LogicExecutionError,
        startedAt: Date
    ) throws -> LogicSynthesisResult {
        LogicSynthesisResult(
            schemaVersion: LogicSynthesisRequest.currentSchemaVersion,
            runID: request.runID,
            status: LogicDiagnosticFactory.status(for: error),
            diagnostics: [LogicDiagnosticFactory.make(for: error)],
            artifacts: [],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "LogicSynthesis",
                    version: implementationVersion,
                    build: "native-lowering-optimization-mapping"
                ),
                inputs: request.inputs,
                invocation: ExecutionInvocation.inProcess(
                    entryPoint: "NativeLogicSynthesisEngine.execute"
                ),
                startedAt: startedAt,
                completedAt: Date()
            ),
            payload: LogicSynthesisPayload(
                mappedDesign: nil,
                mappedCellCount: 0,
                acceptanceState: .rejected
            )
        )
    }

    private func parseParenthesizedName(_ line: String) -> String? {
        guard let start = line.firstIndex(of: "("), let end = line.firstIndex(of: ")"), start < end else { return nil }
        return line[line.index(after: start)..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferKind(from line: String) -> LogicNodeKind? {
        let lower = line.lowercased()
        if lower.contains("&") { return .and }
        if lower.contains("|") { return .or }
        if lower.contains("^") { return .xor }
        if lower.contains("!") { return .not }
        return nil
    }

    private func inferInputCount(from line: String) -> Int {
        let operands = line.split(separator: "&").count
        return max(1, operands)
    }

    private func parseNumber(_ line: String, field: String, path: String) -> Double {
        let value = line
            .split(separator: ":")
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;\""))
        guard let number = Double(value) else { return 0 }
        _ = field
        _ = path
        return number
    }

    private func parseDirectiveDouble(_ tokens: [String], name: String) throws -> Double {
        guard tokens.count > 1, let value = Double(tokens[1]) else {
            throw LogicExecutionError.invalidArtifact("invalid \(name) value")
        }
        return value
    }

    private func isJSONDecodeError(_ error: LogicExecutionError) -> Bool {
        if case .invalidArtifact(let message) = error {
            return message.contains("JSON")
        }
        return false
    }

    private func checkCancellation() throws {
        if Task.isCancelled {
            throw LogicExecutionError.cancelled
        }
    }

    private struct LibraryResult: Sendable {
        let library: LogicCellLibraryDocument
        let digests: [String]
    }

    private struct ConstraintResult: Sendable {
        let constraints: LogicConstraintDocument
        let digest: String
    }

    private struct OptimizationResult: Sendable {
        let design: LogicDesignDocument
        let transformations: [LogicTransformationRecord]
    }

    private struct MappingResult: Sendable {
        let design: LogicDesignDocument
        let cellCount: Int
        let totalArea: Double
        let totalPower: Double
    }
}
