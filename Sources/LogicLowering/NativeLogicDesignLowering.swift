import Foundation
import CircuiteFoundation
import LogicEngineCore
import LogicIR

public struct NativeLogicDesignLowering: LogicDesignLowering {
    public let implementationVersion: String

    public init(implementationVersion: String = "1") {
        self.implementationVersion = implementationVersion
    }

    public func lower(_ snapshot: LogicDesignSnapshot) -> LogicLoweringResult {
        do {
            let sourceDigest = try LogicDesignSnapshotCodec.digest(snapshot)
            var builder = try Builder(
                snapshot: snapshot,
                sourceDigest: sourceDigest,
                implementationVersion: implementationVersion
            )
            let document = try builder.build()
            try document.validate()
            return LogicLoweringResult(
                status: .completed,
                document: document,
                diagnostics: [DesignDiagnostic(
                    code: .trusted("logic.lowering.completed"),
                    severity: .information,
                    summary: "Lowered RTL snapshot \(snapshot.rtl.topModuleName) into the LogicEngine execution graph.",
                    suggestedActions: []
                )]
            )
        } catch let error as LogicLoweringError {
            return result(for: error)
        } catch let error as LogicExecutionError {
            return LogicLoweringResult(
                status: .failed,
                diagnostics: [LogicDiagnosticFactory.make(for: error)]
            )
        } catch {
            return LogicLoweringResult(
                status: .failed,
                diagnostics: [DesignDiagnostic(
                    code: .trusted("logic.lowering.failed"),
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: [
                        SuggestedAction(code: "logic.lowering.inspect-snapshot", summary: "inspect_rtl_snapshot"),
                        SuggestedAction(code: "logic.lowering.validate", summary: "rerun_logic_design_validation")
                    ]
                )]
            )
        }
    }

    private func result(for error: LogicLoweringError) -> LogicLoweringResult {
        let diagnostic: DesignDiagnostic
        let status: LogicEngineCore.LogicExecutionStatus
        switch error {
        case .missingTopModule:
            status = .failed
            diagnostic = DesignDiagnostic(
                code: .trusted(code(for: error)),
                severity: .error,
                summary: error.localizedDescription,
                suggestedActions: [
                    SuggestedAction(code: "logic.lowering.select-top", summary: "select_an_existing_top_module"),
                    SuggestedAction(code: "logic.lowering.elaborate", summary: "rerun_rtl_elaboration")
                ]
            )
        case .unsupported(let entity, _):
            status = .blocked
            diagnostic = DesignDiagnostic(
                code: .trusted(code(for: error)),
                severity: .error,
                summary: error.localizedDescription,
                detail: "entity=\(entity)",
                suggestedActions: [
                    SuggestedAction(code: "logic.lowering.rewrite", summary: "rewrite_into_supported_rtl_subset"),
                    SuggestedAction(code: "logic.lowering.backend", summary: "select_a_backend_with_required_semantics")
                ]
            )
        case .invalidDesign, .widthMismatch, .multipleDriver:
            status = .failed
            diagnostic = DesignDiagnostic(
                code: .trusted(code(for: error)),
                severity: .error,
                summary: error.localizedDescription,
                suggestedActions: [
                    SuggestedAction(code: "logic.lowering.inspect", summary: "inspect_rtl_validation_diagnostics"),
                    SuggestedAction(code: "logic.lowering.repair", summary: "repair_design_and_reelaborate")
                ]
            )
        }
        return LogicLoweringResult(status: status, diagnostics: [diagnostic])
    }

    private func code(for error: LogicLoweringError) -> String {
        switch error {
        case .invalidDesign: return "LOGIC_LOWERING_DESIGN_INVALID"
        case .widthMismatch: return "LOGIC_LOWERING_WIDTH_MISMATCH"
        case .multipleDriver: return "LOGIC_LOWERING_MULTIPLE_DRIVER"
        case .missingTopModule: return "LOGIC_LOWERING_TOP_MISSING"
        case .unsupported: return "LOGIC_LOWERING_UNSUPPORTED_RTL"
        }
    }

    private struct Builder {
        private let module: RTLModule
        private let sourceDigest: String
        private let implementationVersion: String
        private var ports: [LogicPort] = []
        private var signals: [LogicSignal] = []
        private var signalWidths: [String: Int] = [:]
        private var signalSignedness: [String: Bool] = [:]
        private var signalRanges: [String: LogicRange] = [:]
        private var nodes: [LogicNode] = []
        private var drivenSignals: Set<String> = []
        private var intermediateIndex: Int = 0

        init(
            snapshot: LogicDesignSnapshot,
            sourceDigest: String,
            implementationVersion: String
        ) throws {
            guard let module = snapshot.rtl.modules.first(where: { $0.name == snapshot.rtl.topModuleName }) else {
                throw LogicLoweringError.missingTopModule(snapshot.rtl.topModuleName)
            }
            self.module = module
            self.sourceDigest = sourceDigest
            self.implementationVersion = implementationVersion
        }

        mutating func build() throws -> LogicDesignDocument {
            guard module.memories.isEmpty else {
                throw LogicLoweringError.unsupported(entity: module.name, construct: "memory")
            }
            guard module.instances.isEmpty else {
                throw LogicLoweringError.unsupported(entity: module.name, construct: "hierarchical instance")
            }
            guard module.generateBlocks.isEmpty else {
                throw LogicLoweringError.unsupported(entity: module.name, construct: "unelaborated generate block")
            }

            for port in module.ports {
                try addPort(port)
            }
            for signal in module.signals {
                try addSignal(
                    name: signal.name,
                    width: signal.range?.width ?? 1,
                    isSigned: signal.isSigned,
                    range: signal.range
                )
            }
            for assignment in module.assignments {
                try lowerContinuousAssignment(assignment)
            }
            for process in module.processes {
                try lowerProcess(process)
            }

            return LogicDesignDocument(
                topDesignName: module.name,
                ports: ports,
                signals: signals,
                nodes: nodes,
                metadata: [
                    "sourceDesignDigest": sourceDigest,
                    "sourceTopDesignName": module.name,
                    "loweringImplementation": "native-rtl-to-execution-graph",
                    "loweringImplementationVersion": implementationVersion,
                ]
            )
        }

        private mutating func addPort(_ port: RTLPort) throws {
            let width = port.range?.width ?? 1
            try addSignal(name: port.name, width: width, isSigned: port.isSigned, range: port.range)
            let direction: LogicPortDirection
            switch port.direction {
            case .input:
                direction = .input
            case .output:
                direction = .output
            case .inOut:
                direction = .inoutPort
            case .internalSignal:
                throw LogicLoweringError.invalidDesign("port \(port.name) has an internal direction")
            }
            ports.append(LogicPort(name: port.name, direction: direction, width: width))
        }

        private mutating func addSignal(
            name: String,
            width: Int,
            isSigned: Bool = false,
            range: LogicRange? = nil
        ) throws {
            guard width > 0 else {
                throw LogicLoweringError.widthMismatch(entity: name, expected: 1, actual: width)
            }
            if let existingWidth = signalWidths[name] {
                guard existingWidth == width else {
                    throw LogicLoweringError.widthMismatch(entity: name, expected: existingWidth, actual: width)
                }
                if let existingRange = signalRanges[name], let range, existingRange != range {
                    throw LogicLoweringError.invalidDesign("signal \(name) has conflicting ranges")
                }
                guard signalSignedness[name] == isSigned else {
                    throw LogicLoweringError.invalidDesign("signal \(name) has conflicting signedness")
                }
                return
            }
            signalWidths[name] = width
            signalSignedness[name] = isSigned
            if let range {
                signalRanges[name] = range
            }
            signals.append(LogicSignal(name: name, width: width, isSigned: isSigned))
        }

        private mutating func lowerContinuousAssignment(_ assignment: RTLAssignment) throws {
            try lowerAssignment(assignment, sequentialClock: nil, processID: nil)
        }

        private mutating func lowerProcess(_ process: RTLProcess) throws {
            switch process.kind {
            case .combinational:
                try lowerCombinationalProcess(process)
            case .sequential:
                let events = processEvents(for: process)
                guard let clockEvent = events.first, let clockEdge = clockEvent.edge else {
                    throw LogicLoweringError.unsupported(entity: process.id, construct: "missing clock edge")
                }
                guard events.count <= 2, clockEvent.signal != "*" else {
                    throw LogicLoweringError.unsupported(entity: process.id, construct: "ambiguous sequential sensitivity")
                }
                let asynchronousReset = events.count == 2 ? events[1] : nil
                if let asynchronousReset {
                    guard asynchronousReset.signal != "*", asynchronousReset.edge != nil else {
                        throw LogicLoweringError.unsupported(
                            entity: process.id,
                            construct: "ambiguous asynchronous reset sensitivity"
                        )
                    }
                }
                guard allAssignmentsUseNonBlocking(process.statements) else {
                    throw LogicLoweringError.unsupported(
                        entity: process.id,
                        construct: "blocking assignment in sequential process"
                    )
                }
                guard signalWidths[clockEvent.signal] == 1 else {
                    throw LogicLoweringError.widthMismatch(
                        entity: clockEvent.signal,
                        expected: 1,
                        actual: signalWidths[clockEvent.signal] ?? 0
                    )
                }
                if let asynchronousReset {
                    guard signalWidths[asynchronousReset.signal] == 1 else {
                        throw LogicLoweringError.widthMismatch(
                            entity: asynchronousReset.signal,
                            expected: 1,
                            actual: signalWidths[asynchronousReset.signal] ?? 0
                        )
                    }
                }
                let assignments = try lowerStatements(process.statements)
                for target in assignments.keys.sorted() {
                    guard let source = assignments[target] else { continue }
                    try validateAssignmentWidth(target: target, source: source)
                    let resetValue = try asynchronousReset.map { reset in
                        try asynchronousResetValue(
                            in: process.statements,
                            resetSignal: reset.signal,
                            resetEdge: reset.edge ?? .positive,
                            target: target,
                            targetWidth: try signalWidth(target)
                        )
                    }
                    try appendSequentialNode(
                        processID: process.id,
                        target: target,
                        data: source,
                        clock: clockEvent.signal,
                        edge: clockEdge,
                        asynchronousReset: asynchronousReset,
                        resetValue: resetValue
                    )
                }
            case .generic:
                let events = processEvents(for: process)
                guard !events.isEmpty, events.allSatisfy({ $0.edge == nil }) else {
                    throw LogicLoweringError.unsupported(
                        entity: process.id,
                        construct: "edge-sensitive generic process"
                    )
                }
                try lowerCombinationalProcess(process)
            case .latch:
                try lowerLatchProcess(process)
            }
        }

        private mutating func lowerCombinationalProcess(_ process: RTLProcess) throws {
            guard allAssignmentsUseBlocking(process.statements) else {
                throw LogicLoweringError.unsupported(
                    entity: process.id,
                    construct: "non-blocking assignment in combinational process"
                )
            }
            let assignments = try lowerStatements(process.statements)
            for target in assignments.keys.sorted() {
                guard let value = assignments[target] else { continue }
                try drive(target: target, source: value, nodeID: "process-\(process.id)-\(target)")
            }
        }

        private mutating func lowerLatchProcess(_ process: RTLProcess) throws {
            let events = processEvents(for: process)
            guard events.allSatisfy({ $0.edge == nil && $0.signal != "*" }) else {
                throw LogicLoweringError.unsupported(
                    entity: process.id,
                    construct: "ambiguous latch sensitivity"
                )
            }
            guard allAssignmentsUseBlocking(process.statements),
                  process.statements.count == 1,
                  case .conditional(let condition, let ifTrue, let ifFalse) = process.statements[0],
                  ifFalse.isEmpty else {
                throw LogicLoweringError.unsupported(
                    entity: process.id,
                    construct: "latch requires an incomplete level-sensitive conditional"
                )
            }
            let gate: String
            let level: String
            switch condition {
            case .identifier(let signal):
                gate = try existingSignal(signal)
                level = "positive"
            case .unary(let operation, let operand):
                guard operation == "!", case .identifier(let signal) = operand else {
                    throw LogicLoweringError.unsupported(
                        entity: process.id,
                        construct: "latch enable must be a scalar signal"
                    )
                }
                gate = try existingSignal(signal)
                level = "negative"
            default:
                throw LogicLoweringError.unsupported(
                    entity: process.id,
                    construct: "latch enable must be a scalar signal"
                )
            }
            guard try signalWidth(gate) == 1 else {
                throw LogicLoweringError.widthMismatch(
                    entity: process.id,
                    expected: 1,
                    actual: try signalWidth(gate)
                )
            }
            let assignments = try lowerStatements(ifTrue)
            guard !assignments.isEmpty else {
                throw LogicLoweringError.unsupported(
                    entity: process.id,
                    construct: "latch branch has no assignment"
                )
            }
            for target in assignments.keys.sorted() {
                guard let data = assignments[target] else { continue }
                try validateAssignmentWidth(target: target, source: data)
                try appendLatchNode(
                    processID: process.id,
                    target: target,
                    data: data,
                    gate: gate,
                    level: level
                )
            }
        }

        private func allAssignmentsUseBlocking(_ statements: [RTLStatement]) -> Bool {
            statements.allSatisfy { statement in
                switch statement {
                case .assignment(let assignment):
                    return !assignment.nonBlocking
                case .block(let nested):
                    return allAssignmentsUseBlocking(nested)
                case .conditional(_, let ifTrue, let ifFalse):
                    return allAssignmentsUseBlocking(ifTrue) && allAssignmentsUseBlocking(ifFalse)
                case .caseStatement(_, let items, let defaultStatements),
                     .typedCaseStatement(_, _, let items, let defaultStatements):
                    return items.allSatisfy { allAssignmentsUseBlocking($0.statements) }
                        && allAssignmentsUseBlocking(defaultStatements)
                case .null:
                    return true
                }
            }
        }

        private func processEvents(for process: RTLProcess) -> [RTLProcessEvent] {
            if !process.events.isEmpty {
                return process.events
            }
            return process.sensitivity.map { signal in
                RTLProcessEvent(signal: signal, edge: process.clockEdge)
            }
        }

        private func allAssignmentsUseNonBlocking(_ statements: [RTLStatement]) -> Bool {
            statements.allSatisfy { statement in
                switch statement {
                case .assignment(let assignment):
                    return assignment.nonBlocking
                case .block(let nested):
                    return allAssignmentsUseNonBlocking(nested)
                case .conditional(_, let ifTrue, let ifFalse):
                    return allAssignmentsUseNonBlocking(ifTrue) && allAssignmentsUseNonBlocking(ifFalse)
                case .caseStatement(_, let items, let defaultStatements),
                     .typedCaseStatement(_, _, let items, let defaultStatements):
                    return items.allSatisfy { allAssignmentsUseNonBlocking($0.statements) }
                        && allAssignmentsUseNonBlocking(defaultStatements)
                case .null:
                    return true
                }
            }
        }

        private mutating func lowerStatements(_ statements: [RTLStatement]) throws -> [String: String] {
            var assignments: [String: String] = [:]
            for statement in statements {
                switch statement {
                case .assignment(let assignment):
                    guard case .identifier(let target) = assignment.target else {
                        throw LogicLoweringError.unsupported(entity: assignment.id, construct: "indexed assignment target")
                    }
                    guard assignments[target] == nil else {
                        throw LogicLoweringError.multipleDriver(target)
                    }
                    let expression = try lowerExpression(assignment.value, owner: assignment.id)
                    try validateAssignmentWidth(target: target, source: expression.signal)
                    assignments[target] = expression.signal
                case .block(let nested):
                    let nestedAssignments = try lowerStatements(nested)
                    for target in nestedAssignments.keys.sorted() {
                        guard let value = nestedAssignments[target] else { continue }
                        guard assignments[target] == nil else {
                            throw LogicLoweringError.multipleDriver(target)
                        }
                        assignments[target] = value
                    }
                case .conditional(let condition, let ifTrue, let ifFalse):
                    let conditionValue = try lowerExpression(condition, owner: "conditional")
                    guard conditionValue.width == 1 else {
                        throw LogicLoweringError.widthMismatch(entity: "conditional", expected: 1, actual: conditionValue.width)
                    }
                    let trueAssignments = try lowerStatements(ifTrue)
                    let falseAssignments = try lowerStatements(ifFalse)
                    let targets = Set(trueAssignments.keys).union(falseAssignments.keys).sorted()
                    for target in targets {
                        guard let trueValue = trueAssignments[target], let falseValue = falseAssignments[target] else {
                            throw LogicLoweringError.unsupported(entity: target, construct: "incomplete combinational conditional")
                        }
                        let width = try signalWidth(target)
                        guard try signalWidth(trueValue) == width, try signalWidth(falseValue) == width else {
                            throw LogicLoweringError.widthMismatch(entity: target, expected: width, actual: max(try signalWidth(trueValue), try signalWidth(falseValue)))
                        }
                        let merged = try appendNode(
                            id: "mux-\(target)-\(intermediateIndex)",
                            kind: .mux,
                            inputs: [conditionValue.signal, trueValue, falseValue],
                            outputWidth: width
                        )
                        assignments[target] = merged
                    }
                case .caseStatement(let expression, let items, let defaultStatements):
                    let caseAssignments = try lowerCaseStatement(
                        kind: .standard,
                        expression: expression,
                        items: items,
                        defaultStatements: defaultStatements
                    )
                    for target in caseAssignments.keys.sorted() {
                        guard let value = caseAssignments[target] else { continue }
                        guard assignments[target] == nil else {
                            throw LogicLoweringError.multipleDriver(target)
                        }
                        assignments[target] = value
                    }
                case .typedCaseStatement(let kind, let expression, let items, let defaultStatements):
                    let caseAssignments = try lowerCaseStatement(
                        kind: kind,
                        expression: expression,
                        items: items,
                        defaultStatements: defaultStatements
                    )
                    for target in caseAssignments.keys.sorted() {
                        guard let value = caseAssignments[target] else { continue }
                        guard assignments[target] == nil else {
                            throw LogicLoweringError.multipleDriver(target)
                        }
                        assignments[target] = value
                    }
                case .null:
                    continue
                }
            }
            return assignments
        }

        private mutating func lowerCaseStatement(
            kind: RTLCaseKind,
            expression: RTLExpression,
            items: [RTLCaseItem],
            defaultStatements: [RTLStatement]
        ) throws -> [String: String] {
            guard kind == .standard else {
                throw LogicLoweringError.unsupported(entity: module.name, construct: "casex or casez statement")
            }
            let selector = try lowerExpression(expression, owner: "case-selector")
            let fallback = try lowerStatements(defaultStatements)
            guard !fallback.isEmpty else {
                throw LogicLoweringError.unsupported(entity: module.name, construct: "case statement without default assignment")
            }
            let itemAssignments = try items.enumerated().map { index, item in
                (index, try lowerStatements(item.statements))
            }
            let targets = Set(fallback.keys).union(itemAssignments.flatMap { $0.1.keys }).sorted()
            guard targets.allSatisfy({ fallback[$0] != nil }) else {
                throw LogicLoweringError.unsupported(entity: module.name, construct: "case branches with inconsistent targets")
            }

            var result = fallback
            for (index, assignments) in itemAssignments.reversed() {
                let condition = try lowerCaseCondition(
                    selector: selector,
                    matches: items[index].matches,
                    owner: "case-\(index)"
                )
                for target in targets {
                    guard let itemValue = assignments[target], let fallbackValue = result[target] else {
                        throw LogicLoweringError.unsupported(entity: target, construct: "case branch without assignment")
                    }
                    let width = try signalWidth(target)
                    try validateAssignmentWidth(target: target, source: itemValue)
                    try validateAssignmentWidth(target: target, source: fallbackValue)
                    result[target] = try appendNode(
                        id: "case-mux-\(index)-\(target)",
                        kind: .mux,
                        inputs: [condition, itemValue, fallbackValue],
                        outputWidth: width,
                        isSigned: signalSignedness[target] ?? false
                    )
                }
            }
            return result
        }

        private mutating func lowerCaseCondition(
            selector: ExpressionValue,
            matches: [RTLExpression],
            owner: String
        ) throws -> String {
            guard !matches.isEmpty else {
                throw LogicLoweringError.invalidDesign("case item has no match expression")
            }
            let conditions = try matches.enumerated().map { index, match in
                let value = try lowerExpression(match, owner: "\(owner)-match-\(index)")
                guard value.width == selector.width else {
                    throw LogicLoweringError.widthMismatch(entity: owner, expected: selector.width, actual: value.width)
                }
                return try appendNode(
                    id: "case-equal-\(owner)-\(index)",
                    kind: .caseEqual,
                    inputs: [selector.signal, value.signal],
                    outputWidth: 1
                )
            }
            guard conditions.count > 1 else {
                return conditions[0]
            }
            return try appendNode(
                id: "case-or-\(owner)",
                kind: .or,
                inputs: conditions,
                outputWidth: 1
            )
        }

        private mutating func lowerAssignment(
            _ assignment: RTLAssignment,
            sequentialClock: String?,
            processID: String?
        ) throws {
            guard case .identifier(let target) = assignment.target else {
                throw LogicLoweringError.unsupported(entity: assignment.id, construct: "indexed assignment target")
            }
            let expression = try lowerExpression(assignment.value, owner: assignment.id)
            if let sequentialClock {
                try validateAssignmentWidth(target: target, source: expression.signal)
                try appendSequentialNode(
                    processID: processID ?? assignment.id,
                    target: target,
                    data: expression.signal,
                    clock: sequentialClock
                )
            } else {
                try drive(target: target, source: expression.signal, nodeID: "assign-\(assignment.id)")
            }
        }

        private mutating func drive(target: String, source: String, nodeID: String) throws {
            try validateAssignmentWidth(target: target, source: source)
            guard !drivenSignals.contains(target) else {
                throw LogicLoweringError.multipleDriver(target)
            }
            drivenSignals.insert(target)
            guard target != source else { return }
            nodes.append(LogicNode(id: nodeID, kind: .buffer, inputs: [source], outputs: [target]))
        }

        private mutating func appendSequentialNode(
            processID: String,
            target: String,
            data: String,
            clock: String,
            edge: RTLClockEdge = .positive,
            asynchronousReset: RTLProcessEvent? = nil,
            resetValue: String? = nil
        ) throws {
            guard !drivenSignals.contains(target) else {
                throw LogicLoweringError.multipleDriver(target)
            }
            drivenSignals.insert(target)
            var parameters = ["edge": edge.rawValue]
            if let asynchronousReset {
                guard let resetEdge = asynchronousReset.edge else {
                    throw LogicLoweringError.unsupported(
                        entity: processID,
                        construct: "asynchronous reset without an edge"
                    )
                }
                parameters["resetSignal"] = asynchronousReset.signal
                parameters["resetEdge"] = resetEdge.rawValue
                if let resetValue {
                    parameters["resetValue"] = resetValue
                }
            }
            nodes.append(LogicNode(
                id: "dff-\(processID)-\(target)",
                kind: .dff,
                inputs: [data, clock],
                outputs: [target],
                parameters: parameters
            ))
        }

        private mutating func appendLatchNode(
            processID: String,
            target: String,
            data: String,
            gate: String,
            level: String
        ) throws {
            guard !drivenSignals.contains(target) else {
                throw LogicLoweringError.multipleDriver(target)
            }
            drivenSignals.insert(target)
            nodes.append(LogicNode(
                id: "latch-\(processID)-\(target)",
                kind: .latch,
                inputs: [data, gate],
                outputs: [target],
                parameters: ["level": level]
            ))
        }

        private func asynchronousResetValue(
            in statements: [RTLStatement],
            resetSignal: String,
            resetEdge: RTLClockEdge,
            target: String,
            targetWidth: Int
        ) throws -> String {
            guard let conditional = findResetConditional(
                in: statements,
                resetSignal: resetSignal,
                resetEdge: resetEdge
            ) else {
                throw LogicLoweringError.unsupported(
                    entity: target,
                    construct: "asynchronous reset conditional"
                )
            }
            guard let expression = findAssignmentValue(in: conditional.ifTrue, target: target) else {
                throw LogicLoweringError.unsupported(
                    entity: target,
                    construct: "asynchronous reset branch without an assignment"
                )
            }
            guard case .integer(let value, let width, let isSigned) = expression else {
                throw LogicLoweringError.unsupported(
                    entity: target,
                    construct: "non-constant asynchronous reset value"
                )
            }
            guard value >= 0 || isSigned else {
                throw LogicLoweringError.unsupported(
                    entity: target,
                    construct: "negative unsigned asynchronous reset value"
                )
            }
            let literalWidth = width ?? (targetWidth == 1 ? 1 : 0)
            guard literalWidth == targetWidth, targetWidth > 0, targetWidth <= UInt64.bitWidth else {
                throw LogicLoweringError.widthMismatch(
                    entity: target,
                    expected: targetWidth,
                    actual: literalWidth
                )
            }
            let mask = targetWidth == UInt64.bitWidth
                ? UInt64.max
                : (UInt64(1) &<< UInt64(targetWidth)) &- 1
            let bits = UInt64(bitPattern: value) & mask
            let binary = String(bits, radix: 2)
            return String(repeating: "0", count: targetWidth - binary.count) + binary
        }

        private func findResetConditional(
            in statements: [RTLStatement],
            resetSignal: String,
            resetEdge: RTLClockEdge
        ) -> (ifTrue: [RTLStatement], ifFalse: [RTLStatement])? {
            for statement in statements {
                switch statement {
                case .block(let nested):
                    if let result = findResetConditional(
                        in: nested,
                        resetSignal: resetSignal,
                        resetEdge: resetEdge
                    ) {
                        return result
                    }
                case .conditional(let condition, let ifTrue, let ifFalse):
                    if isResetCondition(condition, resetSignal: resetSignal, resetEdge: resetEdge) {
                        return (ifTrue, ifFalse)
                    }
                    if let result = findResetConditional(
                        in: ifTrue,
                        resetSignal: resetSignal,
                        resetEdge: resetEdge
                    ) {
                        return result
                    }
                    if let result = findResetConditional(
                        in: ifFalse,
                        resetSignal: resetSignal,
                        resetEdge: resetEdge
                    ) {
                        return result
                    }
                default:
                    continue
                }
            }
            return nil
        }

        private func isResetCondition(
            _ expression: RTLExpression,
            resetSignal: String,
            resetEdge: RTLClockEdge
        ) -> Bool {
            switch (resetEdge, expression) {
            case (.positive, .identifier(let name)):
                return name == resetSignal
            case (.negative, .unary(let operation, let operand)):
                guard operation == "!", case .identifier(let name) = operand else { return false }
                return name == resetSignal
            default:
                return false
            }
        }

        private func findAssignmentValue(
            in statements: [RTLStatement],
            target: String
        ) -> RTLExpression? {
            for statement in statements {
                switch statement {
                case .assignment(let assignment):
                    guard case .identifier(let name) = assignment.target, name == target else { continue }
                    return assignment.value
                case .block(let nested):
                    if let value = findAssignmentValue(in: nested, target: target) {
                        return value
                    }
                default:
                    continue
                }
            }
            return nil
        }

        private mutating func lowerExpression(_ expression: RTLExpression, owner: String) throws -> ExpressionValue {
            switch expression {
            case .identifier(let name):
                return ExpressionValue(
                    signal: try existingSignal(name),
                    width: try signalWidth(name),
                    isSigned: signalSignedness[name] ?? false
                )
            case .integer(let value, let width, let isSigned):
                guard !(!isSigned && value < 0) else {
                    throw LogicLoweringError.unsupported(entity: owner, construct: "negative unsigned integer literal")
                }
                let literalWidth = try integerLiteralWidth(
                    value: value,
                    requestedWidth: width,
                    isSigned: isSigned,
                    owner: owner
                )
                let mask = literalWidth == UInt64.bitWidth
                    ? UInt64.max
                    : (UInt64(1) &<< UInt64(literalWidth)) &- 1
                let bits = UInt64(bitPattern: value) & mask
                let binary = String(bits, radix: 2)
                let padded = String(repeating: "0", count: literalWidth - binary.count) + binary
                let signal = try appendNode(
                    id: "constant-\(owner)-\(intermediateIndex)",
                    kind: .constant,
                    inputs: [],
                    outputWidth: literalWidth,
                    isSigned: isSigned,
                    parameters: ["value": padded]
                )
                return ExpressionValue(signal: signal, width: literalWidth, isSigned: isSigned)
            case .unary(let operation, let operand):
                let value = try lowerExpression(operand, owner: owner)
                guard operation == "~" || operation == "!" else {
                    throw LogicLoweringError.unsupported(entity: owner, construct: "unary operator \(operation)")
                }
                let isLogicalNot = operation == "!"
                let signal = try appendNode(
                    id: "not-\(owner)-\(intermediateIndex)",
                    kind: isLogicalNot && value.width > 1 ? .logicalNot : .not,
                    inputs: [value.signal],
                    outputWidth: isLogicalNot ? 1 : value.width,
                    isSigned: isLogicalNot ? false : value.isSigned
                )
                return ExpressionValue(
                    signal: signal,
                    width: isLogicalNot ? 1 : value.width,
                    isSigned: isLogicalNot ? false : value.isSigned
                )
            case .binary(let operation, let left, let right):
                let lhs = try lowerExpression(left, owner: owner)
                let rhs = try lowerExpression(right, owner: owner)
                let kind: LogicNodeKind
                let outputWidth: Int
                switch operation {
                case "&": kind = .and; outputWidth = try equalWidth(lhs, rhs, owner: owner)
                case "|": kind = .or; outputWidth = try equalWidth(lhs, rhs, owner: owner)
                case "&&":
                    kind = lhs.width == 1 && rhs.width == 1 ? .and : .logicalAnd
                    outputWidth = 1
                case "||":
                    kind = lhs.width == 1 && rhs.width == 1 ? .or : .logicalOr
                    outputWidth = 1
                case "^": kind = .xor; outputWidth = try equalWidth(lhs, rhs, owner: owner)
                case "~&": kind = .nand; outputWidth = try equalWidth(lhs, rhs, owner: owner)
                case "~|": kind = .nor; outputWidth = try equalWidth(lhs, rhs, owner: owner)
                case "~^", "^~": kind = .xnor; outputWidth = try equalWidth(lhs, rhs, owner: owner)
                case "==": kind = .equal; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case "!=": kind = .notEqual; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case "===": kind = .caseEqual; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case "!==": kind = .caseNotEqual; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case "<": kind = .lessThan; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case "<=": kind = .lessEqual; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case ">": kind = .greaterThan; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case ">=": kind = .greaterEqual; outputWidth = 1; _ = try equalWidth(lhs, rhs, owner: owner)
                case "+": kind = .add; outputWidth = max(lhs.width, rhs.width)
                case "-": kind = .subtract; outputWidth = max(lhs.width, rhs.width)
                case "*": kind = .multiply; outputWidth = lhs.width + rhs.width
                case "/": kind = .divide; outputWidth = max(lhs.width, rhs.width)
                case "%": kind = .modulo; outputWidth = max(lhs.width, rhs.width)
                case "<<": kind = .shiftLeft; outputWidth = lhs.width
                case ">>": kind = .shiftRight; outputWidth = lhs.width
                default:
                    throw LogicLoweringError.unsupported(entity: owner, construct: "binary operator \(operation)")
                }
                let isArithmetic = kind == .add
                    || kind == .subtract
                    || kind == .multiply
                    || kind == .divide
                    || kind == .modulo
                    || kind == .shiftLeft
                    || kind == .shiftRight
                let isLogicalOperation = operation == "&&" || operation == "||"
                let isSignedOperation: Bool
                if kind == .shiftLeft || kind == .shiftRight {
                    isSignedOperation = lhs.isSigned
                } else if kind == .logicalAnd || kind == .logicalOr {
                    isSignedOperation = false
                } else if kind == .and || kind == .or || kind == .xor
                            || kind == .nand || kind == .nor || kind == .xnor {
                    isSignedOperation = !isLogicalOperation && lhs.isSigned && rhs.isSigned
                } else {
                    isSignedOperation = lhs.isSigned && rhs.isSigned
                }
                if isArithmetic {
                    guard outputWidth <= UInt64.bitWidth else {
                        throw LogicLoweringError.unsupported(entity: owner, construct: "arithmetic wider than the native profile")
                    }
                }
                var parameters: [String: String] = [:]
                if isSignedOperation {
                    parameters["signed"] = "true"
                }
                let signal = try appendNode(
                    id: "\(kind.rawValue)-\(owner)-\(intermediateIndex)",
                    kind: kind,
                    inputs: [lhs.signal, rhs.signal],
                    outputWidth: outputWidth,
                    isSigned: isSignedOperation,
                    parameters: parameters
                )
                return ExpressionValue(signal: signal, width: outputWidth, isSigned: isSignedOperation)
            case .ternary(let condition, let ifTrue, let ifFalse):
                let selector = try lowerExpression(condition, owner: owner)
                guard selector.width == 1 else {
                    throw LogicLoweringError.widthMismatch(entity: owner, expected: 1, actual: selector.width)
                }
                let trueValue = try lowerExpression(ifTrue, owner: owner)
                let falseValue = try lowerExpression(ifFalse, owner: owner)
                guard trueValue.width == falseValue.width else {
                    throw LogicLoweringError.widthMismatch(entity: owner, expected: trueValue.width, actual: falseValue.width)
                }
                let signal = try appendNode(
                    id: "mux-\(owner)-\(intermediateIndex)",
                    kind: .mux,
                    inputs: [selector.signal, trueValue.signal, falseValue.signal],
                    outputWidth: trueValue.width,
                    isSigned: trueValue.isSigned && falseValue.isSigned
                )
                return ExpressionValue(
                    signal: signal,
                    width: trueValue.width,
                    isSigned: trueValue.isSigned && falseValue.isSigned
                )
            case .concatenate(let values):
                let loweredValues = try values.map { try lowerExpression($0, owner: owner) }
                let signal = try appendNode(
                    id: "concat-\(owner)-\(intermediateIndex)",
                    kind: .concat,
                    inputs: loweredValues.map(\.signal),
                    outputWidth: loweredValues.reduce(0) { $0 + $1.width }
                )
                return ExpressionValue(
                    signal: signal,
                    width: loweredValues.reduce(0) { $0 + $1.width },
                    isSigned: false
                )
            case .index(let value, let index):
                return try lowerSlice(
                    value: value,
                    selectionMSB: index,
                    selectionLSB: index,
                    owner: owner
                )
            case .partSelect(let value, let msb, let lsb):
                return try lowerSlice(
                    value: value,
                    selectionMSB: msb,
                    selectionLSB: lsb,
                    owner: owner
                )
            case .string:
                throw LogicLoweringError.unsupported(entity: owner, construct: "string literal")
            }
        }

        private mutating func lowerSlice(
            value: RTLExpression,
            selectionMSB: RTLExpression,
            selectionLSB: RTLExpression,
            owner: String
        ) throws -> ExpressionValue {
            guard case .identifier(let sourceName) = value,
                  let sourceRange = signalRanges[sourceName] else {
                throw LogicLoweringError.unsupported(entity: owner, construct: "dynamic or range-less slice")
            }
            guard let selectedMSB = integerValue(selectionMSB),
                  let selectedLSB = integerValue(selectionLSB) else {
                throw LogicLoweringError.unsupported(entity: owner, construct: "dynamic slice index")
            }
            let sourceLowerBound = min(sourceRange.msb, sourceRange.lsb)
            let sourceUpperBound = max(sourceRange.msb, sourceRange.lsb)
            let selectionLowerBound = min(selectedMSB, selectedLSB)
            let selectionUpperBound = max(selectedMSB, selectedLSB)
            guard selectionLowerBound >= sourceLowerBound,
                  selectionUpperBound <= sourceUpperBound else {
                throw LogicLoweringError.invalidDesign("slice selection is outside the source range")
            }
            let outputWidth = abs(selectedMSB - selectedLSB) + 1
            let signal = try appendNode(
                id: "slice-\(owner)-\(intermediateIndex)",
                kind: .slice,
                inputs: [sourceName],
                outputWidth: outputWidth,
                parameters: [
                    "sourceMSB": String(sourceRange.msb),
                    "sourceLSB": String(sourceRange.lsb),
                    "selectionMSB": String(selectedMSB),
                    "selectionLSB": String(selectedLSB),
                ]
            )
            return ExpressionValue(signal: signal, width: outputWidth, isSigned: false)
        }

        private func integerValue(_ expression: RTLExpression) -> Int? {
            guard case .integer(let value, _, _) = expression,
                  value >= 0,
                  value <= Int64(Int.max) else {
                return nil
            }
            return Int(value)
        }

        private func integerLiteralWidth(
            value: Int64,
            requestedWidth: Int?,
            isSigned: Bool,
            owner: String
        ) throws -> Int {
            if let requestedWidth {
                guard requestedWidth > 0, requestedWidth <= UInt64.bitWidth else {
                    throw LogicLoweringError.widthMismatch(entity: owner, expected: 1, actual: requestedWidth)
                }
                if isSigned, requestedWidth < Int64.bitWidth {
                    let minimum = -(Int64(1) &<< UInt64(requestedWidth - 1))
                    let maximum = (Int64(1) &<< UInt64(requestedWidth - 1)) &- 1
                    guard value >= minimum, value <= maximum else {
                        throw LogicLoweringError.widthMismatch(
                            entity: owner,
                            expected: requestedWidth,
                            actual: signedLiteralWidth(value)
                        )
                    }
                } else if !isSigned {
                    let maximumBit = requestedWidth == Int64.bitWidth
                        ? UInt64.max
                        : (UInt64(1) &<< UInt64(requestedWidth)) &- 1
                    guard value >= 0, UInt64(bitPattern: value) <= maximumBit else {
                        throw LogicLoweringError.widthMismatch(
                            entity: owner,
                            expected: requestedWidth,
                            actual: max(1, Int64.bitWidth - value.leadingZeroBitCount)
                        )
                    }
                }
                return requestedWidth
            }
            if isSigned {
                return signedLiteralWidth(value)
            }
            guard value >= 0 else {
                throw LogicLoweringError.unsupported(entity: owner, construct: "negative unsigned integer literal")
            }
            return max(1, Int64.bitWidth - value.leadingZeroBitCount)
        }

        private func signedLiteralWidth(_ value: Int64) -> Int {
            if value == 0 {
                return 1
            }
            if value > 0 {
                return min(Int64.bitWidth, Int64.bitWidth - value.leadingZeroBitCount + 1)
            }
            return max(1, Int64.bitWidth - (~value).leadingZeroBitCount)
        }

        private mutating func appendNode(
            id: String,
            kind: LogicNodeKind,
            inputs: [String],
            outputWidth: Int,
            isSigned: Bool = false,
            parameters: [String: String] = [:]
        ) throws -> String {
            guard outputWidth > 0 else {
                throw LogicLoweringError.widthMismatch(entity: id, expected: 1, actual: outputWidth)
            }
            let output = "__logic_lowered_\(intermediateIndex)"
            intermediateIndex += 1
            try addSignal(name: output, width: outputWidth, isSigned: isSigned)
            nodes.append(LogicNode(id: id, kind: kind, inputs: inputs, outputs: [output], parameters: parameters))
            return output
        }

        private func existingSignal(_ name: String) throws -> String {
            guard signalWidths[name] != nil else {
                throw LogicLoweringError.invalidDesign("unknown RTL signal \(name)")
            }
            return name
        }

        private func signalWidth(_ name: String) throws -> Int {
            guard let width = signalWidths[name] else {
                throw LogicLoweringError.invalidDesign("unknown lowered signal \(name)")
            }
            return width
        }

        private func validateAssignmentWidth(target: String, source: String) throws {
            let targetWidth = try signalWidth(target)
            let sourceWidth = try signalWidth(source)
            guard targetWidth == sourceWidth else {
                throw LogicLoweringError.widthMismatch(entity: target, expected: targetWidth, actual: sourceWidth)
            }
        }

        private func equalWidth(
            _ lhs: ExpressionValue,
            _ rhs: ExpressionValue,
            owner: String
        ) throws -> Int {
            guard lhs.width == rhs.width else {
                throw LogicLoweringError.widthMismatch(entity: owner, expected: lhs.width, actual: rhs.width)
            }
            return lhs.width
        }

        private struct ExpressionValue: Sendable, Hashable {
            let signal: String
            let width: Int
            let isSigned: Bool
        }
    }
}
