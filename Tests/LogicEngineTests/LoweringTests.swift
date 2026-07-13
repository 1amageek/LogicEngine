import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import SystemVerilogFrontend
import Testing

@Suite("LogicDesign to LogicEngine lowering")
struct LoweringTests {
    @Test("lowers a parsed RTL snapshot into a deterministic execution graph")
    func lowersParsedRTL() throws {
        let source = SystemVerilogSourceUnit(
            path: "and.sv",
            source: "module top(input logic a, input logic b, output logic y); assign y = a & b; endmodule"
        )
        let parseResult = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(parseResult.unsupportedSemantics == false)
        #expect(parseResult.diagnostics.isEmpty)
        guard let rtl = parseResult.design else {
            Issue.record("The parser did not produce an RTL design.")
            return
        }
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(rtl: rtl))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.topDesignName == "top")
        #expect(result.document?.ports.count == 3)
        #expect(result.document?.nodes.contains { $0.kind == .and } == true)
        #expect(result.document?.metadata["sourceDesignDigest"] == snapshot.designDigest)
        try result.document?.validate()
    }

    @Test("lowers scalar logical AND and OR without widening them into vector operations")
    func lowersScalarLogicalOperators() throws {
        let module = RTLModule(
            id: "module-logical",
            name: "logical_top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input),
                RTLPort(id: "b", name: "b", direction: .input),
                RTLPort(id: "and", name: "and", direction: .output),
                RTLPort(id: "or", name: "or", direction: .output),
            ],
            assignments: [
                RTLAssignment(
                    id: "assignment-and",
                    target: .identifier("and"),
                    value: .binary(operator: "&&", left: .identifier("a"), right: .identifier("b"))
                ),
                RTLAssignment(
                    id: "assignment-or",
                    target: .identifier("or"),
                    value: .binary(operator: "||", left: .identifier("a"), right: .identifier("b"))
                ),
            ]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "logical_top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .and } == true)
        #expect(result.document?.nodes.contains { $0.kind == .or } == true)
    }

    @Test("lowers comparison, division, modulo, and level-sensitive latch semantics")
    func lowersExtendedExecutionGraphSemantics() throws {
        let module = RTLModule(
            id: "module-extended",
            name: "extended_top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "b", name: "b", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "en", name: "en", direction: .input),
                RTLPort(id: "d", name: "d", direction: .input),
                RTLPort(id: "eq", name: "eq", direction: .output),
                RTLPort(id: "lt", name: "lt", direction: .output),
                RTLPort(id: "quotient", name: "quotient", direction: .output, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "remainder", name: "remainder", direction: .output, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "q", name: "q", direction: .output),
            ],
            assignments: [
                RTLAssignment(
                    id: "assignment-eq",
                    target: .identifier("eq"),
                    value: .binary(operator: "==", left: .identifier("a"), right: .identifier("b"))
                ),
                RTLAssignment(
                    id: "assignment-lt",
                    target: .identifier("lt"),
                    value: .binary(operator: "<", left: .identifier("a"), right: .identifier("b"))
                ),
                RTLAssignment(
                    id: "assignment-quotient",
                    target: .identifier("quotient"),
                    value: .binary(operator: "/", left: .identifier("a"), right: .identifier("b"))
                ),
                RTLAssignment(
                    id: "assignment-remainder",
                    target: .identifier("remainder"),
                    value: .binary(operator: "%", left: .identifier("a"), right: .identifier("b"))
                ),
            ],
            processes: [RTLProcess(
                id: "process-latch",
                kind: .latch,
                sensitivity: ["en", "d"],
                statements: [.conditional(
                    condition: .identifier("en"),
                    ifTrue: [.assignment(RTLAssignment(
                        id: "latch-assignment",
                        target: .identifier("q"),
                        value: .identifier("d")
                    ))],
                    ifFalse: []
                )]
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "extended_top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .equal } == true)
        #expect(result.document?.nodes.contains { $0.kind == .lessThan } == true)
        #expect(result.document?.nodes.contains { $0.kind == .divide } == true)
        #expect(result.document?.nodes.contains { $0.kind == .modulo } == true)
        #expect(result.document?.nodes.contains { $0.kind == .latch } == true)
    }

    @Test("lowers vector logical operators to scalar truth-value nodes")
    func lowersVectorLogicalOperators() throws {
        let module = RTLModule(
            id: "module-vector-logical",
            name: "vector_logical_top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "b", name: "b", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "and", name: "and", direction: .output),
                RTLPort(id: "or", name: "or", direction: .output),
            ],
            assignments: [
                RTLAssignment(
                    id: "assignment-and",
                    target: .identifier("and"),
                    value: .binary(operator: "&&", left: .identifier("a"), right: .identifier("b"))
                ),
                RTLAssignment(
                    id: "assignment-or",
                    target: .identifier("or"),
                    value: .binary(operator: "||", left: .identifier("a"), right: .identifier("b"))
                ),
            ]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "vector_logical_top", modules: [module])
        ))

        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .logicalAnd } == true)
        #expect(result.document?.nodes.contains { $0.kind == .logicalOr } == true)
        #expect(result.document?.nodes.filter { $0.kind == .logicalAnd || $0.kind == .logicalOr }
            .allSatisfy { $0.outputs.count == 1 } == true)
    }

    @Test("lowers vector logical NOT to a scalar truth-value node")
    func lowersVectorLogicalNot() throws {
        let module = RTLModule(
            id: "module-vector-logical-not",
            name: "vector_logical_not_top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "not", name: "not", direction: .output),
            ],
            assignments: [RTLAssignment(
                id: "assignment-not",
                target: .identifier("not"),
                value: .unary(operator: "!", operand: .identifier("a"))
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "vector_logical_not_top", modules: [module])
        ))

        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .logicalNot } == true)
        #expect(result.document?.signals.contains { $0.name == "not" && $0.width == 1 } == true)
    }

    @Test("lowers a hierarchy-elaborated SystemVerilog snapshot")
    func lowersHierarchyElaboratedSnapshot() async throws {
        let source = SystemVerilogSourceUnit(
            path: "hierarchy.sv",
            source: """
            module leaf(input logic a, output logic y);
                assign y = a;
            endmodule
            module top(input logic a, output logic y);
                leaf u_leaf(.a(a), .y(y));
            endmodule
            """
        )
        let elaborated = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "logic-engine-hierarchy",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))
        guard let snapshot = elaborated.payload.snapshot else {
            Issue.record("Expected hierarchy elaboration to produce a canonical snapshot")
            return
        }

        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(elaborated.status == .completed)
        #expect(result.status == .completed)
        #expect(result.document?.topDesignName == "top")
        #expect(result.document?.nodes.contains { $0.kind == .buffer } == true)
    }

    @Test("lowers a parameterized hierarchy snapshot with resolved width")
    func lowersParameterizedHierarchySnapshot() async throws {
        let source = SystemVerilogSourceUnit(
            path: "parameterized-hierarchy.sv",
            source: """
            module leaf #(parameter WIDTH = 1) (
                input logic [WIDTH-1:0] a,
                output logic [WIDTH-1:0] y
            );
                assign y = a;
            endmodule
            module top(input logic [3:0] a, output logic [3:0] y);
                leaf #(.WIDTH(4)) u_leaf(.a(a), .y(y));
            endmodule
            """
        )
        let elaborated = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "logic-engine-parameterized-hierarchy",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))
        guard let snapshot = elaborated.payload.snapshot else {
            Issue.record("Expected parameterized hierarchy elaboration to produce a canonical snapshot")
            return
        }

        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(elaborated.status == .completed)
        #expect(result.status == .completed)
        #expect(result.document?.signals.contains {
            $0.name == "u_leaf__y" && $0.width == 4
        } == true)
    }

    @Test("lowers a complete always-comb conditional from SystemVerilog")
    func lowersCompleteAlwaysCombConditional() async throws {
        let source = SystemVerilogSourceUnit(
            path: "always-comb.sv",
            source: """
            module top(input logic select, input logic a, input logic b, output logic y);
                always_comb begin
                    if (select) begin
                        y = a;
                    end else begin
                        y = b;
                    end
                end
            endmodule
            """
        )
        let elaborated = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "logic-engine-always-comb",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))
        guard let snapshot = elaborated.payload.snapshot else {
            Issue.record("Expected always-comb elaboration to produce a canonical snapshot")
            return
        }

        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(elaborated.status == .completed)
        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .mux } == true)
    }

    @Test("lowers a generic always-star combinational process and blocks NBA form")
    func lowersGenericAlwaysStarProcess() async throws {
        let source = SystemVerilogSourceUnit(
            path: "always-star.sv",
            source: "module top(input logic a, input logic b, output logic y); always @* begin y = a | b; end endmodule"
        )
        let elaborated = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "logic-engine-always-star",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))
        guard let snapshot = elaborated.payload.snapshot else {
            Issue.record("Expected generic always-star elaboration to produce a canonical snapshot")
            return
        }
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(elaborated.status == .completed)
        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .or } == true)

        let nonBlockingSource = SystemVerilogSourceUnit(
            path: "always-star-nba.sv",
            source: "module top(input logic a, output logic y); always @* begin y <= a; end endmodule"
        )
        let nonBlockingElaborated = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "logic-engine-always-star-nba",
            inputs: [],
            topDesignName: "top",
            sources: [nonBlockingSource]
        ))
        guard let nonBlockingSnapshot = nonBlockingElaborated.payload.snapshot else {
            Issue.record("Expected generic always-star NBA elaboration to produce a canonical snapshot")
            return
        }
        let nonBlockingResult = NativeLogicDesignLowering().lower(nonBlockingSnapshot)

        #expect(nonBlockingElaborated.status == .completed)
        #expect(nonBlockingResult.status == .blocked)
        #expect(nonBlockingResult.diagnostics.contains { $0.code.rawValue == "LOGIC_LOWERING_UNSUPPORTED_RTL" })
    }

    @Test("lowers a generic explicit sensitivity-list process")
    func lowersGenericSensitivityListProcess() async throws {
        let source = SystemVerilogSourceUnit(
            path: "always-sensitivity-list.sv",
            source: "module top(input logic a, input logic b, output logic y); always @(a or b) begin y = a ^ b; end endmodule"
        )
        let elaborated = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "logic-engine-always-sensitivity-list",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))

        #expect(elaborated.status == .completed)
        let snapshot = try #require(elaborated.payload.snapshot)
        let process = try #require(snapshot.rtl.modules.first?.processes.first)
        #expect(process.kind == .generic)
        #expect(process.sensitivity == ["a", "b"])
        #expect(process.events.map(\.signal) == ["a", "b"])
        #expect(process.events.allSatisfy { $0.edge == nil })

        let result = NativeLogicDesignLowering().lower(snapshot)
        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .xor } == true)
    }

    @Test("lowering is deterministic for the same finalized snapshot")
    func loweringIsDeterministic() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input),
                RTLPort(id: "b", name: "b", direction: .input),
                RTLPort(id: "y", name: "y", direction: .output),
            ],
            assignments: [RTLAssignment(
                id: "assignment-y",
                target: .identifier("y"),
                value: .binary(operator: "^", left: .identifier("a"), right: .identifier("b"))
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))

        let first = NativeLogicDesignLowering().lower(snapshot)
        let second = NativeLogicDesignLowering().lower(snapshot)

        #expect(first.status == .completed)
        #expect(first.document == second.document)
        #expect(first.diagnostics == second.diagnostics)
    }

    @Test("reports a width mismatch instead of relying on runtime broadcasting")
    func rejectsWidthMismatch() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "y", name: "y", direction: .output),
            ],
            assignments: [RTLAssignment(
                id: "assignment-y",
                target: .identifier("y"),
                value: .identifier("a")
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code.rawValue == "LOGIC_LOWERING_WIDTH_MISMATCH" })
    }

    @Test("lowers concatenation and static vector projections")
    func lowersConcatenationAndSlices() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "bus", name: "bus", direction: .input, range: LogicRange(msb: 3, lsb: 0)),
                RTLPort(id: "a", name: "a", direction: .input),
                RTLPort(id: "b", name: "b", direction: .input),
                RTLPort(id: "pair", name: "pair", direction: .output, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "bit", name: "bit", direction: .output),
            ],
            assignments: [
                RTLAssignment(
                    id: "assignment-pair",
                    target: .identifier("pair"),
                    value: .concatenate([.identifier("a"), .identifier("b")])
                ),
                RTLAssignment(
                    id: "assignment-bit",
                    target: .identifier("bit"),
                    value: .index(
                        value: .identifier("bus"),
                        index: .integer(value: 1, width: nil, isSigned: false)
                    )
                ),
            ]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .concat } == true)
        #expect(result.document?.nodes.contains { $0.kind == .slice } == true)
    }

    @Test("lowers a plain case statement into case-equality and mux nodes")
    func lowersPlainCaseStatement() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "sel", name: "sel", direction: .input),
                RTLPort(id: "a", name: "a", direction: .input),
                RTLPort(id: "y", name: "y", direction: .output),
            ],
            processes: [RTLProcess(
                id: "process-y",
                kind: .combinational,
                statements: [.typedCaseStatement(
                    kind: .standard,
                    expression: .identifier("sel"),
                    items: [RTLCaseItem(
                        matches: [.integer(value: 1, width: 1, isSigned: false)],
                        statements: [.assignment(RTLAssignment(
                            id: "case-true",
                            target: .identifier("y"),
                            value: .identifier("a")
                        ))]
                    )],
                    defaultStatements: [.assignment(RTLAssignment(
                        id: "case-default",
                        target: .identifier("y"),
                        value: .integer(value: 0, width: 1, isSigned: false)
                    ))]
                )]
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .caseEqual } == true)
        #expect(result.document?.nodes.contains { $0.kind == .mux } == true)
    }

    @Test("blocks casex semantics instead of treating wildcard matching as exact matching")
    func blocksWildcardCaseStatement() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "sel", name: "sel", direction: .input),
                RTLPort(id: "y", name: "y", direction: .output),
            ],
            processes: [RTLProcess(
                id: "process-y",
                kind: .combinational,
                statements: [.typedCaseStatement(
                    kind: .x,
                    expression: .identifier("sel"),
                    items: [],
                    defaultStatements: [.assignment(RTLAssignment(
                        id: "case-default",
                        target: .identifier("y"),
                        value: .integer(value: 0, width: 1, isSigned: false)
                    ))]
                )]
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "LOGIC_LOWERING_UNSUPPORTED_RTL" })
    }

    @Test("lowers a positive-edge sequential process to a DFF")
    func lowersPositiveEdgeSequentialProcess() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "clk", name: "clk", direction: .input),
                RTLPort(id: "d", name: "d", direction: .input),
                RTLPort(id: "q", name: "q", direction: .output),
            ],
            processes: [RTLProcess(
                id: "process-q",
                kind: .sequential,
                sensitivity: ["clk"],
                clockEdge: .positive,
                statements: [.assignment(RTLAssignment(
                    id: "assignment-q",
                    target: .identifier("q"),
                    value: .identifier("d"),
                    nonBlocking: true
                ))]
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .dff } == true)
        #expect(result.document?.nodes.first(where: { $0.kind == .dff })?.parameters["edge"] == "positive")
    }

    @Test("blocks blocking assignments in sequential processes")
    func blocksBlockingSequentialAssignment() throws {
        let module = RTLModule(
            id: "module-blocking",
            name: "blocking_top",
            ports: [
                RTLPort(id: "clk", name: "clk", direction: .input),
                RTLPort(id: "d", name: "d", direction: .input),
                RTLPort(id: "q", name: "q", direction: .output),
            ],
            processes: [RTLProcess(
                id: "process-q",
                kind: .sequential,
                sensitivity: ["clk"],
                clockEdge: .positive,
                statements: [.assignment(RTLAssignment(
                    id: "assignment-q",
                    target: .identifier("q"),
                    value: .identifier("d"),
                    nonBlocking: false
                ))]
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "blocking_top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "LOGIC_LOWERING_UNSUPPORTED_RTL" })
    }

    @Test("rejects multiple drivers during RTL lowering")
    func rejectsMultipleDrivers() throws {
        let module = RTLModule(
            id: "module-multiple-driver",
            name: "multiple_driver_top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input),
                RTLPort(id: "b", name: "b", direction: .input),
                RTLPort(id: "y", name: "y", direction: .output),
            ],
            assignments: [
                RTLAssignment(id: "assignment-a", target: .identifier("y"), value: .identifier("a")),
                RTLAssignment(id: "assignment-b", target: .identifier("y"), value: .identifier("b")),
            ]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "multiple_driver_top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code.rawValue == "LOGIC_LOWERING_MULTIPLE_DRIVER" })
    }

    @Test("lowers synchronous reset into a data-path mux before the DFF")
    func lowersSynchronousReset() throws {
        let source = SystemVerilogSourceUnit(
            path: "reset.sv",
            source: "module top(input logic clk, input logic reset, input logic d, output logic q); always_ff @(posedge clk) begin if (reset) q <= 1'b0; else q <= d; end endmodule"
        )
        let parseResult = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(parseResult.diagnostics.isEmpty)
        guard let rtl = parseResult.design else {
            Issue.record("The parser did not produce a reset RTL design.")
            return
        }
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(rtl: rtl))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .mux } == true)
        #expect(result.document?.nodes.contains { $0.kind == .dff } == true)
    }

    @Test("lowers an asynchronous reset event into a reset-qualified DFF")
    func lowersAsynchronousReset() throws {
        let source = SystemVerilogSourceUnit(
            path: "async-reset.sv",
            source: "module top(input logic clk, input logic reset_n, input logic d, output logic q); always_ff @(posedge clk or negedge reset_n) begin if (!reset_n) q <= 1'b0; else q <= d; end endmodule"
        )
        let parseResult = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(parseResult.diagnostics.isEmpty)
        guard let rtl = parseResult.design else {
            Issue.record("The parser did not produce an asynchronous reset RTL design.")
            return
        }
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(rtl: rtl))
        let result = NativeLogicDesignLowering().lower(snapshot)
        let dff = result.document?.nodes.first(where: { $0.kind == .dff })

        #expect(result.status == .completed)
        #expect(dff?.parameters["edge"] == "positive")
        #expect(dff?.parameters["resetSignal"] == "reset_n")
        #expect(dff?.parameters["resetEdge"] == "negative")

        let nonZeroSource = SystemVerilogSourceUnit(
            path: "async-reset-one.sv",
            source: source.source.replacingOccurrences(of: "1'b0", with: "1'b1")
        )
        let nonZeroParseResult = SystemVerilogParser().parse([nonZeroSource], topDesignName: "top")
        #expect(nonZeroParseResult.diagnostics.isEmpty)
        guard let nonZeroRTL = nonZeroParseResult.design else {
            Issue.record("The parser did not produce the non-zero asynchronous reset RTL design.")
            return
        }
        let nonZeroSnapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(rtl: nonZeroRTL))
        let nonZeroResult = NativeLogicDesignLowering().lower(nonZeroSnapshot)
        let nonZeroDFF = nonZeroResult.document?.nodes.first(where: { $0.kind == .dff })

        #expect(nonZeroResult.status == .completed)
        #expect(nonZeroDFF?.parameters["resetValue"] == "1")
    }

    @Test("rejects a non-scalar asynchronous reset control")
    func rejectsVectorAsynchronousReset() throws {
        let module = RTLModule(
            id: "module-async-reset-width",
            name: "async_reset_width_top",
            ports: [
                RTLPort(id: "clk", name: "clk", direction: .input),
                RTLPort(id: "reset", name: "reset", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "d", name: "d", direction: .input),
                RTLPort(id: "q", name: "q", direction: .output),
            ],
            processes: [RTLProcess(
                id: "process-q",
                kind: .sequential,
                sensitivity: ["clk", "reset"],
                clockEdge: .positive,
                events: [
                    RTLProcessEvent(signal: "clk", edge: .positive),
                    RTLProcessEvent(signal: "reset", edge: .negative),
                ],
                statements: [.assignment(RTLAssignment(
                    id: "assignment-q",
                    target: .identifier("q"),
                    value: .identifier("d"),
                    nonBlocking: true
                ))]
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "async_reset_width_top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code.rawValue == "LOGIC_LOWERING_WIDTH_MISMATCH" })
    }

    @Test("lowers unsigned and signed arithmetic with explicit signedness")
    func lowersArithmeticProfile() throws {
        let unsignedModule = RTLModule(
            id: "module-unsigned",
            name: "unsigned_top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "b", name: "b", direction: .input, range: LogicRange(msb: 1, lsb: 0)),
                RTLPort(id: "y", name: "y", direction: .output, range: LogicRange(msb: 1, lsb: 0)),
            ],
            assignments: [RTLAssignment(
                id: "assignment-y",
                target: .identifier("y"),
                value: .binary(operator: "+", left: .identifier("a"), right: .identifier("b"))
            )]
        )
        let unsignedSnapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "unsigned_top", modules: [unsignedModule])
        ))
        let unsignedResult = NativeLogicDesignLowering().lower(unsignedSnapshot)
        #expect(unsignedResult.status == .completed)
        #expect(unsignedResult.document?.nodes.contains { $0.kind == .add } == true)

        let signedModule = RTLModule(
            id: "module-signed",
            name: "signed_top",
            ports: [
                RTLPort(id: "a", name: "a", direction: .input, range: LogicRange(msb: 1, lsb: 0), isSigned: true),
                RTLPort(id: "b", name: "b", direction: .input, range: LogicRange(msb: 1, lsb: 0), isSigned: true),
                RTLPort(id: "y", name: "y", direction: .output, range: LogicRange(msb: 1, lsb: 0), isSigned: true),
            ],
            assignments: [RTLAssignment(
                id: "assignment-y",
                target: .identifier("y"),
                value: .binary(operator: "+", left: .identifier("a"), right: .identifier("b"))
            )]
        )
        let signedSnapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "signed_top", modules: [signedModule])
        ))
        let signedResult = NativeLogicDesignLowering().lower(signedSnapshot)
        #expect(signedResult.status == .completed)
        #expect(signedResult.document?.signals.contains { $0.name == "a" && $0.isSigned } == true)
        #expect(signedResult.document?.signals.contains { $0.name.hasPrefix("__logic_lowered_") && $0.isSigned } == true)
        #expect(signedResult.document?.nodes.contains {
            $0.kind == .add && $0.parameters["signed"] == "true"
        } == true)
    }

    @Test("lowers signed negative literals without losing their bit pattern")
    func lowersSignedNegativeLiteral() throws {
        let module = RTLModule(
            id: "module-signed-literal",
            name: "signed_literal_top",
            ports: [
                RTLPort(id: "y", name: "y", direction: .output, range: LogicRange(msb: 3, lsb: 0), isSigned: true),
            ],
            assignments: [RTLAssignment(
                id: "assignment-y",
                target: .identifier("y"),
                value: .integer(value: -1, width: 4, isSigned: true)
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "signed_literal_top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains {
            $0.kind == .constant && $0.parameters["value"] == "1111"
        } == true)
        #expect(result.document?.signals.contains {
            $0.name.hasPrefix("__logic_lowered_") && $0.isSigned
        } == true)
    }

    @Test("lowers a negative-edge sequential process to an edge-qualified DFF")
    func lowersNegativeEdgeProcess() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "clk", name: "clk", direction: .input),
                RTLPort(id: "d", name: "d", direction: .input),
                RTLPort(id: "q", name: "q", direction: .output),
            ],
            processes: [RTLProcess(
                id: "process-q",
                kind: .sequential,
                sensitivity: ["clk"],
                clockEdge: .negative,
                statements: [.assignment(RTLAssignment(
                    id: "assignment-q",
                    target: .identifier("q"),
                    value: .identifier("d"),
                    nonBlocking: true
                ))]
            )]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .completed)
        #expect(result.document?.nodes.contains { $0.kind == .dff } == true)
        #expect(result.document?.nodes.first(where: { $0.kind == .dff })?.parameters["edge"] == "negative")
    }

    @Test("blocks retained case and latch semantics instead of silently changing behavior")
    func blocksUnpreservedControlFlow() throws {
        let module = RTLModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "sel", name: "sel", direction: .input),
                RTLPort(id: "a", name: "a", direction: .input),
                RTLPort(id: "y", name: "y", direction: .output),
            ],
            processes: [RTLProcess(
                id: "process-case",
                kind: .combinational,
                statements: [.caseStatement(
                    expression: .identifier("sel"),
                    items: [RTLCaseItem(
                        matches: [.integer(value: 1, width: nil, isSigned: false)],
                        statements: [.assignment(RTLAssignment(
                            id: "case-assignment",
                            target: .identifier("y"),
                            value: .identifier("a")
                        ))]
                    )],
                    defaultStatements: [.assignment(RTLAssignment(
                        id: "case-default",
                        target: .identifier("y"),
                        value: .identifier("a")
                    ))]
                )]
            ), RTLProcess(id: "process-latch", kind: .latch)]
        )
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [module])
        ))
        let result = NativeLogicDesignLowering().lower(snapshot)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "LOGIC_LOWERING_UNSUPPORTED_RTL" })
    }
}
