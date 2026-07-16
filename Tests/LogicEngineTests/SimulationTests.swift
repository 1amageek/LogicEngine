import Foundation
import LogicEngineCore
import LogicIR
import LogicSimulation
import Testing
import CircuiteFoundation

@Suite("Native logic simulation")
struct SimulationTests {
    @Test("evaluates comparisons, division, modulo, and level-sensitive latches")
    func evaluatesExtendedExecutionGraphSemantics() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-extended-semantics-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove extended semantics simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "extended_top",
            ports: [
                LogicPort(name: "a", direction: .input, width: 2),
                LogicPort(name: "b", direction: .input, width: 2),
                LogicPort(name: "en", direction: .input),
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "eq", direction: .output),
                LogicPort(name: "lt", direction: .output),
                LogicPort(name: "quotient", direction: .output, width: 2),
                LogicPort(name: "remainder", direction: .output, width: 2),
                LogicPort(name: "q", direction: .output),
            ],
            signals: [
                LogicSignal(name: "a", width: 2),
                LogicSignal(name: "b", width: 2),
                LogicSignal(name: "en"),
                LogicSignal(name: "d"),
                LogicSignal(name: "eq"),
                LogicSignal(name: "lt"),
                LogicSignal(name: "quotient", width: 2),
                LogicSignal(name: "remainder", width: 2),
                LogicSignal(name: "q"),
            ],
            nodes: [
                LogicNode(id: "eq", kind: .equal, inputs: ["a", "b"], outputs: ["eq"]),
                LogicNode(id: "lt", kind: .lessThan, inputs: ["a", "b"], outputs: ["lt"]),
                LogicNode(id: "divide", kind: .divide, inputs: ["a", "b"], outputs: ["quotient"]),
                LogicNode(id: "modulo", kind: .modulo, inputs: ["a", "b"], outputs: ["remainder"]),
                LogicNode(
                    id: "latch",
                    kind: .latch,
                    inputs: ["d", "en"],
                    outputs: ["q"],
                    parameters: ["level": "positive"]
                ),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "a": try LogicVector(string: "01"),
                    "b": try LogicVector(string: "10"),
                    "en": LogicVector(.one),
                    "d": LogicVector(.one),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "en": LogicVector(.zero),
                    "d": LogicVector(.zero),
                ]),
                LogicStimulusEvent(time: 2, assignments: [
                    "en": LogicVector(.one),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "equal", time: 0, signal: "eq", expected: LogicVector(.zero)),
                LogicAssertion(id: "less-than", time: 0, signal: "lt", expected: LogicVector(.one)),
                LogicAssertion(id: "divide", time: 0, signal: "quotient", expected: try LogicVector(string: "00")),
                LogicAssertion(id: "modulo", time: 0, signal: "remainder", expected: try LogicVector(string: "01")),
                LogicAssertion(id: "latch-open", time: 0, signal: "q", expected: LogicVector(.one)),
                LogicAssertion(id: "latch-hold", time: 1, signal: "q", expected: LogicVector(.one)),
                LogicAssertion(id: "latch-update", time: 2, signal: "q", expected: LogicVector(.zero)),
            ]
        )
        let designReference = try writeJSON(design, name: "extended-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "extended-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "extended-semantics-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "extended_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        #expect(
            result.status == .completed,
            "Diagnostics: \(result.diagnostics)"
        )
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("evaluates unsigned arithmetic and propagates unknown operands")
    func evaluatesUnsignedArithmetic() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-arithmetic-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove arithmetic simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "arithmetic_top",
            ports: [
                LogicPort(name: "a", direction: .input, width: 2),
                LogicPort(name: "b", direction: .input, width: 2),
                LogicPort(name: "y", direction: .output, width: 2),
            ],
            signals: [
                LogicSignal(name: "a", width: 2),
                LogicSignal(name: "b", width: 2),
                LogicSignal(name: "y", width: 2),
            ],
            nodes: [LogicNode(id: "add0", kind: .add, inputs: ["a", "b"], outputs: ["y"])]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "a": try LogicVector(string: "01"),
                    "b": try LogicVector(string: "10"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "a": try LogicVector(string: "0X"),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "sum", time: 0, signal: "y", expected: try LogicVector(string: "11")),
                LogicAssertion(id: "unknown-sum", time: 1, signal: "y", expected: try LogicVector(string: "XX")),
            ]
        )
        let designReference = try writeJSON(design, name: "arithmetic-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "arithmetic-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "arithmetic-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "arithmetic_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("evaluates vector logical operators with four-state truth semantics")
    func evaluatesVectorLogicalOperators() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-vector-logical-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove vector logical simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "vector_logical_top",
            ports: [
                LogicPort(name: "a", direction: .input, width: 2),
                LogicPort(name: "b", direction: .input, width: 2),
                LogicPort(name: "and", direction: .output),
                LogicPort(name: "or", direction: .output),
                LogicPort(name: "not", direction: .output),
            ],
            signals: [
                LogicSignal(name: "a", width: 2),
                LogicSignal(name: "b", width: 2),
                LogicSignal(name: "and"),
                LogicSignal(name: "or"),
                LogicSignal(name: "not"),
            ],
            nodes: [
                LogicNode(id: "logical-and", kind: .logicalAnd, inputs: ["a", "b"], outputs: ["and"]),
                LogicNode(id: "logical-or", kind: .logicalOr, inputs: ["a", "b"], outputs: ["or"]),
                LogicNode(id: "logical-not", kind: .logicalNot, inputs: ["a"], outputs: ["not"]),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "a": try LogicVector(string: "00"),
                    "b": try LogicVector(string: "0X"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "a": try LogicVector(string: "01"),
                    "b": try LogicVector(string: "0X"),
                ]),
                LogicStimulusEvent(time: 2, assignments: [
                    "a": try LogicVector(string: "0X"),
                    "b": try LogicVector(string: "00"),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "zero-and-unknown", time: 0, signal: "and", expected: LogicVector(.zero)),
                LogicAssertion(id: "zero-or-unknown", time: 0, signal: "or", expected: LogicVector(.unknown)),
                LogicAssertion(id: "zero-not", time: 0, signal: "not", expected: LogicVector(.one)),
                LogicAssertion(id: "one-and-unknown", time: 1, signal: "and", expected: LogicVector(.unknown)),
                LogicAssertion(id: "one-or-unknown", time: 1, signal: "or", expected: LogicVector(.one)),
                LogicAssertion(id: "one-not", time: 1, signal: "not", expected: LogicVector(.zero)),
                LogicAssertion(id: "unknown-and-zero", time: 2, signal: "and", expected: LogicVector(.zero)),
                LogicAssertion(id: "unknown-or-zero", time: 2, signal: "or", expected: LogicVector(.unknown)),
                LogicAssertion(id: "unknown-not", time: 2, signal: "not", expected: LogicVector(.unknown)),
            ]
        )
        let designReference = try writeJSON(design, name: "vector-logical-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "vector-logical-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "vector-logical-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "vector_logical_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("evaluates signed arithmetic, sign extension, and arithmetic right shift")
    func evaluatesSignedArithmetic() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-signed-arithmetic-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove signed arithmetic simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "signed_arithmetic_top",
            ports: [
                LogicPort(name: "a", direction: .input, width: 4),
                LogicPort(name: "b", direction: .input, width: 2),
                LogicPort(name: "amount", direction: .input),
                LogicPort(name: "sum", direction: .output, width: 4),
                LogicPort(name: "shifted", direction: .output, width: 4),
            ],
            signals: [
                LogicSignal(name: "a", width: 4, isSigned: true),
                LogicSignal(name: "b", width: 2, isSigned: true),
                LogicSignal(name: "amount"),
                LogicSignal(name: "sum", width: 4, isSigned: true),
                LogicSignal(name: "shifted", width: 4, isSigned: true),
            ],
            nodes: [
                LogicNode(
                    id: "signed-add",
                    kind: .add,
                    inputs: ["a", "b"],
                    outputs: ["sum"],
                    parameters: ["signed": "true"]
                ),
                LogicNode(
                    id: "arithmetic-shift-right",
                    kind: .shiftRight,
                    inputs: ["a", "amount"],
                    outputs: ["shifted"],
                    parameters: ["signed": "true"]
                ),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "a": try LogicVector(string: "1100"),
                    "b": try LogicVector(string: "01"),
                    "amount": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "a": try LogicVector(string: "1X00"),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "signed-sum", time: 0, signal: "sum", expected: try LogicVector(string: "1101")),
                LogicAssertion(id: "arithmetic-shift", time: 0, signal: "shifted", expected: try LogicVector(string: "1110")),
                LogicAssertion(id: "signed-unknown-sum", time: 1, signal: "sum", expected: try LogicVector(string: "XXXX")),
                LogicAssertion(id: "signed-unknown-shift", time: 1, signal: "shifted", expected: try LogicVector(string: "XXXX")),
            ]
        )
        let designReference = try writeJSON(design, name: "signed-arithmetic-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "signed-arithmetic-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "signed-arithmetic-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "signed_arithmetic_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        let reportData = try Data(contentsOf: root.appending(path: "outputs/logic-simulation-report.json"))
        let report = try JSONDecoder().decode(LogicSimulationReport.self, from: reportData)
        for assertion in report.assertions where !assertion.passed {
            Issue.record(
                "Signed arithmetic assertion \(assertion.assertionID) observed \(assertion.observed?.description ?? "nil") expected \(assertion.expected.description)."
            )
        }
        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("applies synchronous reset through the lowered data path")
    func simulatesSynchronousReset() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-reset-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove reset simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "reset_top",
            ports: [
                LogicPort(name: "reset", direction: .input),
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "clk", direction: .input),
                LogicPort(name: "q", direction: .output),
            ],
            signals: [
                LogicSignal(name: "reset"),
                LogicSignal(name: "d"),
                LogicSignal(name: "clk"),
                LogicSignal(name: "zero"),
                LogicSignal(name: "next"),
                LogicSignal(name: "q"),
            ],
            nodes: [
                LogicNode(id: "zero0", kind: .constant, inputs: [], outputs: ["zero"], parameters: ["value": "0"]),
                LogicNode(id: "reset-mux", kind: .mux, inputs: ["reset", "zero", "d"], outputs: ["next"]),
                LogicNode(id: "q0", kind: .dff, inputs: ["next", "clk"], outputs: ["q"]),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "reset": try LogicVector(string: "1"),
                    "d": try LogicVector(string: "1"),
                    "clk": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 1, assignments: ["clk": try LogicVector(string: "1")]),
                LogicStimulusEvent(time: 2, assignments: [
                    "reset": try LogicVector(string: "0"),
                    "clk": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 3, assignments: ["clk": try LogicVector(string: "1")]),
            ],
            assertions: [
                LogicAssertion(id: "reset-edge", time: 1, signal: "q", expected: try LogicVector(string: "0")),
                LogicAssertion(id: "data-edge", time: 3, signal: "q", expected: try LogicVector(string: "1")),
            ]
        )
        let designReference = try writeJSON(design, name: "reset-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "reset-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "reset-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "reset_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("applies an explicit DFF reset only on a rising edge")
    func appliesExplicitDFFResetOnEdge() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-dff-reset-edge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove DFF reset simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "dff_reset_top",
            ports: [
                LogicPort(name: "reset", direction: .input),
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "clk", direction: .input),
                LogicPort(name: "q", direction: .output),
            ],
            signals: [
                LogicSignal(name: "reset"),
                LogicSignal(name: "d"),
                LogicSignal(name: "clk"),
                LogicSignal(name: "q"),
            ],
            nodes: [LogicNode(
                id: "q0",
                kind: .dff,
                inputs: ["d", "clk"],
                outputs: ["q"],
                parameters: ["resetSignal": "reset"]
            )]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "reset": try LogicVector(string: "0"),
                    "d": try LogicVector(string: "0"),
                    "clk": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "d": try LogicVector(string: "1"),
                    "clk": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 2, assignments: [
                    "reset": try LogicVector(string: "1"),
                    "clk": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 3, assignments: ["clk": try LogicVector(string: "1")]),
            ],
            assertions: [
                LogicAssertion(id: "data-edge", time: 1, signal: "q", expected: try LogicVector(string: "1")),
                LogicAssertion(id: "reset-between-edges", time: 2, signal: "q", expected: try LogicVector(string: "1")),
                LogicAssertion(id: "reset-edge", time: 3, signal: "q", expected: try LogicVector(string: "0")),
            ]
        )
        let designReference = try writeJSON(design, name: "dff-reset-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "dff-reset-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "dff-reset-edge-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "dff_reset_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("applies an asynchronous reset without requiring a clock edge")
    func appliesAsynchronousReset() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-async-reset-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove asynchronous-reset simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "async_reset_top",
            ports: [
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "clk", direction: .input),
                LogicPort(name: "reset_n", direction: .input),
                LogicPort(name: "q", direction: .output),
            ],
            signals: [
                LogicSignal(name: "d"),
                LogicSignal(name: "clk"),
                LogicSignal(name: "reset_n"),
                LogicSignal(name: "q"),
            ],
            nodes: [
                LogicNode(
                    id: "async-dff",
                    kind: .dff,
                    inputs: ["d", "clk"],
                    outputs: ["q"],
                    parameters: [
                        "edge": "positive",
                        "resetSignal": "reset_n",
                        "resetEdge": "negative",
                        "resetValue": "1",
                    ]
                ),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "d": try LogicVector(string: "0"),
                    "clk": try LogicVector(string: "0"),
                    "reset_n": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "d": try LogicVector(string: "0"),
                    "clk": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 2, assignments: [
                    "reset_n": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 3, assignments: [
                    "reset_n": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 4, assignments: [
                    "clk": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 5, assignments: [
                    "clk": try LogicVector(string: "1"),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "data-edge", time: 1, signal: "q", expected: LogicVector(.zero)),
                LogicAssertion(id: "reset-without-clock", time: 2, signal: "q", expected: LogicVector(.one)),
                LogicAssertion(id: "reset-release-holds", time: 3, signal: "q", expected: LogicVector(.one)),
                LogicAssertion(id: "post-reset-clock", time: 5, signal: "q", expected: LogicVector(.zero)),
            ]
        )
        let designReference = try writeJSON(design, name: "async-reset-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "async-reset-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "async-reset-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "async_reset_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("evaluates exact case matching without treating unknowns as wildcards")
    func evaluatesCaseEquality() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-case-equality-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove case-equality simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "case_top",
            ports: [
                LogicPort(name: "sel", direction: .input, width: 2),
                LogicPort(name: "match", direction: .input, width: 2),
                LogicPort(name: "y", direction: .output),
            ],
            signals: [
                LogicSignal(name: "sel", width: 2),
                LogicSignal(name: "match", width: 2),
                LogicSignal(name: "eq"),
                LogicSignal(name: "y"),
            ],
            nodes: [
                LogicNode(id: "eq0", kind: .caseEqual, inputs: ["sel", "match"], outputs: ["eq"]),
                LogicNode(id: "buffer0", kind: .buffer, inputs: ["eq"], outputs: ["y"]),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "sel": try LogicVector(string: "1X"),
                    "match": try LogicVector(string: "1X"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "sel": try LogicVector(string: "10"),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "equal-with-x", time: 0, signal: "y", expected: try LogicVector(string: "1")),
                LogicAssertion(id: "different-value", time: 1, signal: "y", expected: try LogicVector(string: "0")),
            ]
        )
        let designReference = try writeJSON(design, name: "case-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "case-stimulus.json", root: root, kind: .testPattern)
        let request = LogicSimulationRequest(
            runID: "case-equality-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "case_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        )
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("samples sequential inputs before applying non-blocking updates")
    func samplesSequentialUpdates() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-sequential-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove sequential simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "sequential_top",
            ports: [
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "clk", direction: .input),
                LogicPort(name: "q1", direction: .output),
                LogicPort(name: "q2", direction: .output),
            ],
            signals: [
                LogicSignal(name: "d"),
                LogicSignal(name: "clk"),
                LogicSignal(name: "q1"),
                LogicSignal(name: "q2"),
            ],
            nodes: [
                LogicNode(id: "dff1", kind: .dff, inputs: ["d", "clk"], outputs: ["q1"]),
                LogicNode(id: "dff2", kind: .dff, inputs: ["q1", "clk"], outputs: ["q2"]),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "d": try LogicVector(string: "0"),
                    "clk": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "d": try LogicVector(string: "1"),
                    "clk": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 2, assignments: [
                    "clk": try LogicVector(string: "0"),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "q1-at-edge", time: 1, signal: "q1", expected: try LogicVector(string: "1")),
                LogicAssertion(id: "q2-at-edge", time: 1, signal: "q2", expected: try LogicVector(string: "X")),
            ]
        )
        let designReference = try writeJSON(design, name: "sequential-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "sequential-stimulus.json", root: root, kind: .testPattern)
        let request = LogicSimulationRequest(
            runID: "sequential-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "sequential_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        )
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("updates a negative-edge DFF only on a falling clock transition")
    func samplesNegativeEdgeUpdates() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-negative-edge-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove negative-edge simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "negative_edge_top",
            ports: [
                LogicPort(name: "d", direction: .input),
                LogicPort(name: "clk", direction: .input),
                LogicPort(name: "q", direction: .output),
            ],
            signals: [
                LogicSignal(name: "d"),
                LogicSignal(name: "clk"),
                LogicSignal(name: "q"),
            ],
            nodes: [
                LogicNode(
                    id: "negative-dff",
                    kind: .dff,
                    inputs: ["d", "clk"],
                    outputs: ["q"],
                    parameters: ["edge": "negative"]
                ),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [
                LogicStimulusEvent(time: 0, assignments: [
                    "d": try LogicVector(string: "0"),
                    "clk": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 1, assignments: [
                    "d": try LogicVector(string: "1"),
                    "clk": try LogicVector(string: "0"),
                ]),
                LogicStimulusEvent(time: 2, assignments: [
                    "d": try LogicVector(string: "0"),
                    "clk": try LogicVector(string: "1"),
                ]),
                LogicStimulusEvent(time: 3, assignments: [
                    "clk": try LogicVector(string: "0"),
                ]),
            ],
            assertions: [
                LogicAssertion(id: "first-falling-edge", time: 1, signal: "q", expected: LogicVector(.one)),
                LogicAssertion(id: "rising-edge-does-not-update", time: 2, signal: "q", expected: LogicVector(.one)),
                LogicAssertion(id: "second-falling-edge", time: 3, signal: "q", expected: LogicVector(.zero)),
            ]
        )
        let designReference = try writeJSON(design, name: "negative-edge-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "negative-edge-stimulus.json", root: root, kind: .testPattern)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "negative-edge-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "negative_edge_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
    }

    @Test("evaluates concatenation and static slice nodes")
    func evaluatesVectorNodes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-vector-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove vector simulation root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "vector_top",
            ports: [
                LogicPort(name: "bus", direction: .input, width: 4),
                LogicPort(name: "a", direction: .input),
                LogicPort(name: "b", direction: .input),
                LogicPort(name: "pair", direction: .output, width: 2),
                LogicPort(name: "bit", direction: .output),
            ],
            signals: [
                LogicSignal(name: "bus", width: 4),
                LogicSignal(name: "a"),
                LogicSignal(name: "b"),
                LogicSignal(name: "pair", width: 2),
                LogicSignal(name: "bit"),
                LogicSignal(name: "__concat", width: 2),
                LogicSignal(name: "__slice"),
            ],
            nodes: [
                LogicNode(id: "concat0", kind: .concat, inputs: ["a", "b"], outputs: ["__concat"]),
                LogicNode(id: "pair0", kind: .buffer, inputs: ["__concat"], outputs: ["pair"]),
                LogicNode(
                    id: "slice0",
                    kind: .slice,
                    inputs: ["bus"],
                    outputs: ["__slice"],
                    parameters: [
                        "sourceMSB": "3",
                        "sourceLSB": "0",
                        "selectionMSB": "1",
                        "selectionLSB": "1",
                    ]
                ),
                LogicNode(id: "bit0", kind: .buffer, inputs: ["__slice"], outputs: ["bit"]),
            ]
        )
        let stimulus = LogicStimulusDocument(
            events: [LogicStimulusEvent(
                time: 0,
                assignments: [
                    "bus": try LogicVector(string: "1010"),
                    "a": try LogicVector(string: "1"),
                    "b": try LogicVector(string: "0"),
                ]
            )],
            assertions: [
                LogicAssertion(id: "pair", time: 0, signal: "pair", expected: try LogicVector(string: "10")),
                LogicAssertion(id: "bit", time: 0, signal: "bit", expected: try LogicVector(string: "1")),
            ]
        )
        let designReference = try writeJSON(design, name: "vector-design.json", root: root, kind: .netlist)
        let stimulusReference = try writeJSON(stimulus, name: "vector-stimulus.json", root: root, kind: .testPattern)
        let request = LogicSimulationRequest(
            runID: "vector-simulation",
            inputs: [designReference, stimulusReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "vector_top",
                designRevision: designReference.digest
            ),
            stimulus: stimulusReference,
            artifactDirectory: "outputs"
        )
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(request)
        let expectedPair = try LogicVector(string: "10")
        let expectedBit = try LogicVector(string: "1")

        #expect(result.status == .completed)
        #expect(result.payload.assertionFailureCount == 0)
        #expect(result.payload.finalValues["pair"] == expectedPair)
        #expect(result.payload.finalValues["bit"] == expectedBit)
    }

    @Test("runs deterministic four-state simulation and writes review artifacts")
    func simulationProducesArtifacts() async throws {
        let design = try LogicEngineTestFixture.designReference()
        let stimulus = try LogicEngineTestFixture.reference(named: "and-stimulus", kind: .testPattern)
        let outputDirectory = try LogicEngineTestFixture.temporaryOutputDirectory()
        let request = LogicSimulationRequest(
            runID: "logic-simulation-fixture",
            inputs: [design.artifact, stimulus],
            design: design,
            stimulus: stimulus,
            seed: 42,
            artifactDirectory: outputDirectory.path(percentEncoded: false)
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: URL(fileURLWithPath: "/"))
        let result = try await NativeLogicSimulationEngine(artifactStore: store).execute(request)

        #expect(
            result.status == .completed,
            "Diagnostics: \(result.diagnostics)"
        )
        #expect(result.payload.traceCount == 3)
        #expect(result.payload.assertionFailureCount == 0)
        let one = try LogicVector(string: "1")
        #expect(result.payload.finalValues["y"] == one)
        #expect(result.artifacts.count == 2)
        guard let waveform = result.payload.waveform else {
            Issue.record("waveform artifact is missing")
            return
        }
        let waveformText = try String(contentsOf: URL(fileURLWithPath: waveform.path), encoding: .utf8)
        #expect(waveformText.contains("$enddefinitions $end"))
        #expect(waveformText.contains("#10"))
    }

    @Test("unsupported semantics are blocked with a structured diagnostic")
    func unsupportedSemanticsAreBlocked() async throws {
        let design = try LogicEngineTestFixture.designReference(named: "unsupported-design")
        let request = LogicSimulationRequest(
            runID: "logic-simulation-unsupported",
            inputs: [design.artifact],
            design: design
        )
        let store = FileSystemLogicArtifactStore(rootDirectory: URL(fileURLWithPath: "/"))
        let result = try await NativeLogicSimulationEngine(artifactStore: store).execute(request)

        #expect(
            result.status == .blocked,
            "Diagnostics: \(result.diagnostics)"
        )
        #expect(result.diagnostics.first?.code.rawValue == "LOGIC_SEMANTICS_UNSUPPORTED")
        #expect(result.payload.traceCount == 0)
    }

    @Test("persists a structured cancellation record")
    func persistsCancellationRecord() async throws {
        let outputDirectory = try LogicEngineTestFixture.temporaryOutputDirectory()
        defer {
            do {
                try FileManager.default.removeItem(at: outputDirectory)
            } catch {
                Issue.record("Failed to remove cancellation output directory: \(error)")
            }
        }
        let design = try LogicEngineTestFixture.designReference()
        let request = LogicSimulationRequest(
            runID: "logic-simulation-cancelled",
            inputs: [design.artifact],
            design: design,
            artifactDirectory: outputDirectory.path(percentEncoded: false)
        )
        let task = Task {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch is CancellationError {
                // The cancellation is intentionally preserved for the engine boundary.
            } catch {
                throw error
            }
            return try await NativeLogicSimulationEngine(
                artifactStore: FileSystemLogicArtifactStore(
                    rootDirectory: outputDirectory,
                    defaultOutputDirectory: outputDirectory
                )
            ).execute(request)
        }
        task.cancel()
        let result = try await task.value

        #expect(result.status == .cancelled)
        guard let cancellation = result.payload.cancellationRecord else {
            Issue.record("cancellation record is missing")
            return
        }
        let cancellationURL = try cancellation.locator.location.resolvedFileURL(
            relativeTo: outputDirectory
        )
        let data = try Data(contentsOf: cancellationURL)
        let record = try JSONDecoder().decode(LogicCancellationRecord.self, from: data)
        #expect(record.runID == request.runID)
        #expect(record.engineID == "LogicSimulation")
    }

    @Test("rejects combinational cycles before simulation")
    func rejectsCombinationalCycle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-cycle-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove combinational cycle root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "cycle_top",
            ports: [LogicPort(name: "y", direction: .output)],
            signals: [
                LogicSignal(name: "a"),
                LogicSignal(name: "b"),
                LogicSignal(name: "y"),
            ],
            nodes: [
                LogicNode(id: "a-from-b", kind: .buffer, inputs: ["b"], outputs: ["a"]),
                LogicNode(id: "b-from-a", kind: .buffer, inputs: ["a"], outputs: ["b"]),
                LogicNode(id: "y-from-a", kind: .buffer, inputs: ["a"], outputs: ["y"]),
            ]
        )
        let designReference = try writeJSON(design, name: "cycle-design.json", root: root, kind: .netlist)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "cycle-simulation",
            inputs: [designReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "cycle_top",
                designRevision: designReference.digest
            ),
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .failed)
        #expect(result.diagnostics.first?.code.rawValue == "LOGIC_COMBINATIONAL_CYCLE")
    }

    @Test("rejects multiple output drivers before simulation")
    func rejectsMultipleOutputDrivers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "logic-multiple-driver-simulation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove multiple-driver root: \(error)")
            }
        }

        let design = LogicDesignDocument(
            topDesignName: "multiple_driver_top",
            ports: [LogicPort(name: "y", direction: .output)],
            signals: [
                LogicSignal(name: "a"),
                LogicSignal(name: "b"),
                LogicSignal(name: "y"),
            ],
            nodes: [
                LogicNode(id: "a-to-y", kind: .buffer, inputs: ["a"], outputs: ["y"]),
                LogicNode(id: "b-to-y", kind: .buffer, inputs: ["b"], outputs: ["y"]),
            ]
        )
        let designReference = try writeJSON(design, name: "multiple-driver-design.json", root: root, kind: .netlist)
        let result = try await NativeLogicSimulationEngine(
            artifactStore: FileSystemLogicArtifactStore(rootDirectory: root)
        ).execute(LogicSimulationRequest(
            runID: "multiple-driver-simulation",
            inputs: [designReference],
            design: LogicDesignArtifact(
                artifact: designReference,
                topDesignName: "multiple_driver_top",
                designRevision: designReference.digest
            ),
            artifactDirectory: "outputs"
        ))

        #expect(result.status == .failed)
        #expect(result.diagnostics.first?.code.rawValue == "LOGIC_DESIGN_INVALID")
    }

    private func writeJSON<T: Encodable>(
        _ value: T,
        name: String,
        root: URL,
        kind: ArtifactKind
    ) throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: root.appending(path: name), options: [.atomic])
        return ArtifactReference(
            id: try ArtifactID(rawValue: name),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: name),
                role: .input,
                kind: kind,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count)
        )
    }
}
