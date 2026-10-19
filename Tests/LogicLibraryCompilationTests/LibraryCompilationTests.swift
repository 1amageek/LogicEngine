import Testing
import Synchronization
import CircuiteFoundation
import CircuiteFoundationCrypto
import LogicIR
import LogicKernelCore
import TimingCore
import LogicEngineRuntime
import LogicSimulation
import LogicSynthesis
import LogicProof
import LogicProofProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct LibraryCompilationTests {
    private struct Control: LogicRunControlling {
        let cancelled: Bool
        func checkpoint() throws(LogicKernelError) { if cancelled { throw .cancelled } }
    }
    private final class Resources: LibertySourceResourceAccounting {
        private struct State { var bytes: UInt64 = 0; var work: UInt64 = 0 }
        private let state = Mutex(State())
        func check() throws {}
        func chargeWork(_ count: UInt64) throws {
            try state.withLock { state in
                let next = state.work.addingReportingOverflow(count)
                guard !next.overflow, next.partialValue <= 10_000_000 else { throw LogicKernelError.invalidInput("Test parse work exceeded") }
                state.work = next.partialValue
            }
        }
        func reserveStorage(kind: LibertySourceStorageKind, byteCount: UInt64) throws -> LibertySourceStorageReservation {
            try state.withLock { state in
                let next = state.bytes.addingReportingOverflow(byteCount)
                guard !next.overflow, next.partialValue <= 10_000_000 else { throw LogicKernelError.invalidInput("Test parse storage exceeded") }
                state.bytes = next.partialValue
            }
            return .init(kind: kind, byteCount: byteCount) { [self] in state.withLock { $0.bytes -= byteCount } }
        }
    }
    private func context(limit: UInt64 = 10_000_000, cancelled: Bool = false) throws -> LogicKernelContext {
        .init(limits: try .init(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, limit) })),
              control: Control(cancelled: cancelled))
    }
    private func parse(_ text: String) throws -> (OwnedLibertySource, ArtifactID) {
        let bytes = Array(text.utf8)
        let digest = try SHA256ContentDigester().digest(using: .sha256,
            limits: .init(maximumChunkByteCount: UInt64(bytes.count), maximumTotalByteCount: UInt64(bytes.count), maximumUpdateCount: 1)) {
                lease throws(ContentDigestError) in try lease.update(bytes)
            }
        return (try LibertyParser().parseSource(bytes.span, limits: .init(maximumNestingDepth: 64), resources: Resources()),
                try .init(digest: digest.digest, byteCount: UInt64(bytes.count)))
    }
    private func compile(_ text: String, context: inout LogicKernelContext, base: UInt64 = 100) throws -> LogicLibraryCompilation {
        let (source, identity) = try parse(text)
        let compiler: any LogicTechnologyLibraryCompiling = NativeLogicTechnologyLibraryCompiler()
        return try compiler.compile(source, identity: identity, options: .init(firstEntityID: .init(rawValue: base)), context: &context)
    }
    private func evaluate(_ function: LogicBooleanFunction, bits: Int) -> Bool {
        function.withOperations { operations in
            var values = [Bool](repeating: false, count: operations.count)
            for index in operations.indices {
                switch operations[index] {
                case .constant(let v): values[index] = v
                case .input(let slot): values[index] = bits & (1 << slot) != 0
                case .invert(let a): values[index] = !values[a.rawValue]
                case .and(let a, let b): values[index] = values[a.rawValue] && values[b.rawValue]
                case .or(let a, let b): values[index] = values[a.rawValue] || values[b.rawValue]
                case .xor(let a, let b): values[index] = values[a.rawValue] != values[b.rawValue]
                }
            }
            return values[function.output.rawValue]
        }
    }
    @Test func actualLibertyEnableFFDrivesMappedEvents() throws {
        var run = try context()
        let result = try compile("""
        library(L){cell(F){area:1;ff(S,SN){next_state:"EN D + EN' S";clocked_on:"C";clear:"!RN";}
        pin(Q){direction:output;function:"S";}pin(D){direction:input;}pin(EN){direction:input;}
        pin(C){direction:input;}pin(RN){direction:input;}}}
        """, context: &run)
        let library = try #require(result.library)
        var builder = try MappedGateBuilder(library: library, capacity: .init(nets: 5, instances: 1, pinConnections: 5, ports: 5, portBits: 5), context: &run)
        for index in 0..<4 { _ = try builder.addNet(.init(id: .init(rawValue: UInt64(500 + index)), driver: .input), context: &run) }
        _ = try builder.addNet(.init(id: .init(rawValue: 504), driver: .instanceOutput(.init(0), .init(0))), context: &run)
        _ = try builder.addInstance(id: .init(rawValue: 600), cell: .init(0), pinNets: [.init(4),.init(0),.init(1),.init(2),.init(3)], stateID: .init(rawValue: 601), context: &run)
        for index in 0..<5 { try builder.addPort(id: .init(rawValue: UInt64(700 + index)), direction: index < 4 ? .input : .output, nets: [.init(index)], context: &run) }
        let graph = try builder.finish(context: &run)
        let model = try NativeLogicSimulationCompiler().compile(graph, library: library, context: &run)
        let evaluator = NativeLogicSimulationEvaluator()
        var state = try evaluator.makeState(model, context: &run)
        for (inputs, expected) in [([1,1,0,0],0),([1,0,0,1],0),([1,0,1,1],0),([1,1,0,1],0),
                                   ([1,1,1,1],1),([0,0,0,1],1),([0,0,1,1],1),([1,1,1,0],0),([1,1,1,1],0)] {
            var updates: [LogicInputEvent.Update] = []
            for index in inputs.indices {
                updates.append(.init(portIndex: index, value: try .init(repeating: inputs[index] == 0 ? .zero : .one, width: .init(1), context: &run)))
            }
            let output = try evaluator.evaluate(model, event: .init(time: 0, updates: updates), state: &state, context: &run)
            #expect(try output.output(at: 0).value.bit(at: 0) == (expected == 0 ? .zero : .one))
        }
    }

    @Test func pinLevelPowerDownNeverPublishesAnUnconditionalFunctionalLibrary() throws {
        for function in ["1", "!A"] {
            var run = try context()
            let result = try compile("""
            library(L){cell(CONDITIONAL){area:1;
              pg_pin(VPWR){pg_type:primary_power;}
              pg_pin(VGND){pg_type:primary_ground;}
              pin(A){direction:input;}
              pin(Y){direction:output;function:"\(function)";power_down_function:"!VPWR + VGND";}
            }}
            """, context: &run)
            #expect(result.library == nil)
            result.withCells { cells in
                #expect(cells.count == 1)
                guard case .ineligible = cells[0].outcome else {
                    Issue.record("Pin-level power-down source became an unconditional actual-cell model")
                    return
                }
            }
        }
    }

    @Test func explicitSourceConditionsPreserveEveryBinaryFunctionAndState() throws {
        let text = """
        library(L){cell(F){area:1;pg_pin(VPWR){pg_type:primary_power;}pg_pin(VGND){pg_type:primary_ground;}
        ff(S,SN){next_state:"EN D + EN' S";clocked_on:"C";clear:"!RN";power_down_function:"!VPWR + VGND";}
        pin(Q){direction:output;function:"S";power_down_function:"!VPWR + VGND";}
        pin(D){direction:input;}pin(EN){direction:input;}pin(C){direction:input;}pin(RN){direction:input;}}}
        """
        let (source, identity) = try parse(text)
        let reference = ArtifactReference(id: identity, descriptor: .init(role: .input, kind: .rtl, format: .liberty))
        let policy = LogicOperatingConditionPolicy(library: reference, cell: "F", conditions: [
            .init(pin: "VPWR", sourcePGType: "primary_power", value: true),
            .init(pin: "VGND", sourcePGType: "primary_ground", value: false)])
        var run = try context()
        let compilation = try NativeLogicTechnologyLibraryCompiler().compile(source, identity: identity,
            options: .init(firstEntityID: .init(rawValue: 100), operatingConditionPolicies: [policy]), context: &run)
        let cell = try #require(compilation.library).cell(at: .init(0))
        let state = try #require(cell.state)
        #expect(state.control == .flipFlop(clock: .init(3), risingEdge: true))
        #expect(state.asynchronousReset == .init(pin: .init(4), activeHigh: false, value: false))
        for bits in 0..<64 {
            let q = bits & 32 != 0, d = bits & 2 != 0, en = bits & 4 != 0
            #expect(evaluate(state.nextState, bits: bits) == (en ? d : q))
            #expect(evaluate(try #require(cell.pin(at: .init(0)).function), bits: bits) == q)
        }
    }

    @Test func unusedPoliciesAndPGOnlyCellsCannotBypassSourceValidation() throws {
        let text = """
        library(L){cell(T){area:1;pin(Y){direction:output;function:"1";}}
        cell(U){area:1;pg_pin(VPWR){pg_type:primary_power;}pg_pin(VGND){pg_type:primary_ground;}
        pin(A){direction:input;}pin(Y){direction:output;function:"!A";power_down_function:"!VPWR + VGND";}}
        cell(P){area:1;pg_pin(VPWR){pg_type:primary_power;}pin(Y){direction:output;function:"0";}}}
        """
        let (source, identity) = try parse(text)
        let reference = ArtifactReference(id: identity, descriptor: .init(role: .input, kind: .rtl, format: .liberty))
        let valid: [LibertyPGCondition] = [.init(pin: "VPWR", sourcePGType: "primary_power", value: true),
            .init(pin: "VGND", sourcePGType: "primary_ground", value: false)]
        var noPolicy = try context()
        let unconditional = try NativeLogicTechnologyLibraryCompiler().compile(source, identity: identity,
            options: .init(firstEntityID: .init(rawValue: 100)), context: &noPolicy)
        #expect(try #require(unconditional.library).cellCount == 1)
        #expect(unconditional.withCells { $0[2].outcome } == .ineligible(.requiresOperatingConditions))
        let invalid: [[LibertyPGCondition]] = [[], Array(valid.prefix(1)), valid + [valid[0]],
            [.init(pin: "VPWR", sourcePGType: "primary_ground", value: true), valid[1]],
            [valid[0], .init(pin: "A", sourcePGType: "primary_ground", value: false)],
            [.init(pin: "VPWR", sourcePGType: "primary_power", value: false), valid[1]]]
        for conditions in invalid {
            var run = try context()
            let policy = LogicOperatingConditionPolicy(library: reference, cell: "U", conditions: conditions)
            #expect(throws: LogicLibraryCompilationError.self) {
                try NativeLogicTechnologyLibraryCompiler().compile(source, identity: identity,
                    options: .init(firstEntityID: .init(rawValue: 100), operatingConditionPolicies: [policy]), context: &run)
            }
        }
        for cell in ["UNKNOWN", "U"] {
            var run = try context()
            let policy = LogicOperatingConditionPolicy(library: reference, cell: cell, conditions: valid)
            #expect(throws: LogicLibraryCompilationError.self) {
                try NativeLogicTechnologyLibraryCompiler().compile(source, identity: identity,
                    options: .init(firstEntityID: .init(rawValue: 100), operatingConditionPolicies: cell == "U" ? [policy, policy] : [policy]), context: &run)
            }
        }
    }
    @Test func actualPinsMultiOutputsAndConstantsPreserveFunction() throws {
        var run = try context()
        let result = try compile("""
        library(L){cell(N){area:2.5;pin(Y){direction:output;function:"!(B A)";}
          pin(A){direction:input;}pin(B){direction:input;}pin(Z){direction:output;function:"A ^ B";}}
          cell(T){area:0;pin(Y){direction:output;function:"1";}}}
        """, context: &run)
        let library = try #require(result.library)
        #expect(library.source == result.source && result.cellCount == 2)
        let first = try library.cell(at: .init(0))
        #expect(first.name == "N" && first.area == 2.5)
        #expect(try first.pin(at: .init(0)).name == "Y")
        for bits in 0..<16 {
            #expect(evaluate(try #require(first.pin(at: .init(0)).function), bits: bits) == !(bits & 2 != 0 && bits & 4 != 0))
            #expect(evaluate(try #require(first.pin(at: .init(3)).function), bits: bits) == ((bits & 2 != 0) != (bits & 4 != 0)))
        }
        #expect(evaluate(try #require(library.cell(at: .init(1)).pin(at: .init(0)).function), bits: 0))
        #expect(try library.cell(at: .init(1)).id.rawValue == 105)
    }
    @Test func stateFeedbackComplementClockGateAndResetAreExact() throws {
        for latch in [false, true] {
            var run = try context()
            let group = latch ? "latch(S,SN){data_in:\"D EN + S EN'\";enable:\"!C\";preset:\"RN'\";}" :
                "ff(S,SN){next_state:\"D EN + S EN'\";clocked_on:\"!C\";clear:\"RN'\";}"
            let result = try compile("library(L){cell(F){area:1;\(group)pin(QN){direction:output;function:\"SN\";}pin(C){direction:input;}pin(RN){direction:input;}pin(D){direction:input;}pin(EN){direction:input;}pin(Q){direction:output;function:\"S\";}}}", context: &run)
            let cell = try #require(result.library).cell(at: .init(0))
            let state = try #require(cell.state)
            #expect(state.control == (latch ? .latch(gate: .init(1), activeHigh: false) : .flipFlop(clock: .init(1), risingEdge: false)))
            #expect(state.asynchronousReset == .init(pin: .init(2), activeHigh: false, value: latch))
            for bits in 0..<128 {
                let q = bits & 64 != 0; let d = bits & 8 != 0; let en = bits & 16 != 0
                #expect(evaluate(state.nextState, bits: bits) == (en ? d : q))
                #expect(evaluate(try #require(cell.pin(at: .init(0)).function), bits: bits) == !q)
            }
        }
    }
    @Test func ineligibleCellsHaveReasonsAndKeepCanonicalSourceOrder() throws {
        let cases: [(String, LogicLibraryCellEligibility.Reason)] = [
            ("dont_use:true;area:1;pin(Y){direction:output;function:\"1\";}", .dontUse),
            ("pin(Y){direction:output;function:\"1\";}", .missingArea),
            ("area:1;pin(Y){direction:output;}", .missingOutputFunction("Y")),
            ("area:1;pin(Y){direction:output;function:\"A\";}", .unknownSymbol("A")),
            ("area:1;pin(Y){direction:output;function:\"1\";three_state:\"A\";}", .unsupportedPinExtension("Y")),
            ("area:1;ff(S,SN){next_state:\"D\";clocked_on:\"C\";power_down_function:\"P\";}pin(Q){direction:output;function:\"S\";}", .unsupportedPowerDown),
            ("area:1;pin(Y){direction:output;function:\"Y\";}", .outputPinReference("Y")),
            ("area:1;bus(B){}pin(Y){direction:output;function:\"1\";}", .unsupportedFunctionalGroup("bus"))]
        for (body, reason) in cases {
            var run = try context()
            let rejected = try compile("library(L){cell(BAD){\(body)}}", context: &run)
            #expect(rejected.library == nil)
            #expect(rejected.withCells { $0[0].outcome } == .ineligible(reason))
        }
        var run = try context()
        let result = try compile("library(L){cell(SKIP){dont_use:true;pin(Y){direction:output;}}cell(T){area:1;pin(Y){direction:output;function:\"0\";}}}", context: &run)
        #expect(try #require(result.library).cell(at: .init(0)).id.rawValue == 102)
        #expect(result.withCells { $0[1].outcome } == .eligible(.init(0)))
    }
    @Test func compoundControlsAndAmbiguousStateSymbolsAreRefused() throws {
        for body in [
            "ff(S,SN){next_state:\"D\";clocked_on:\"C D\";}",
            "ff(C,SN){next_state:\"D\";clocked_on:\"C\";}",
            "ff(S,SN){next_state:\"D\";clocked_on:\"C\";clear:\"C\";}",
            "ff(S,SN){next_state:\"D\";clocked_on:\"C\";clear:\"D\";preset:\"C\";}" ] {
            var run = try context()
            let result = try compile("library(L){cell(F){area:1;\(body)pin(C){direction:input;}pin(D){direction:input;}pin(Q){direction:output;function:\"S\";}}}", context: &run)
            #expect(result.library == nil)
        }
    }
    @Test func forgedSourceAndByteCountAreRejectedBeforePublishing() throws {
        let (source, identity) = try parse("library(L){cell(T){area:1;pin(Y){direction:output;function:\"1\";}}}")
        let forged = try ArtifactID(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "00", count: 32)), byteCount: identity.byteCount)
        let wrongSize = try ArtifactID(digest: identity.digest, byteCount: identity.byteCount + 1)
        for wrong in [forged, wrongSize] {
            var run = try context()
            #expect(throws: LogicLibraryCompilationError.self) {
                try NativeLogicTechnologyLibraryCompiler().compile(source, identity: wrong, options: .init(firstEntityID: .init(rawValue: 100)), context: &run)
            }
        }
    }
    @Test func cancellationBudgetsDuplicateNamesAndIDOverflowNeverSucceed() throws {
        let text = "library(L){cell(T){area:1;pin(Y){direction:output;function:\"1\";}}}"
        for (limit, cancelled) in [(UInt64(1), false), (10_000_000, true)] {
            var run = try context(limit: limit, cancelled: cancelled)
            #expect(throws: LogicLibraryCompilationError.self) { try compile(text, context: &run) }
        }
        var run = try context()
        #expect(throws: LogicLibraryCompilationError.self) { try compile(text, context: &run, base: .max) }
        #expect(throws: LibertySourceError.self) { try compile("library(L){cell(T){area:1;pin(Y){direction:output;function:\"1\";}}cell(T){area:1;pin(Y){direction:output;function:\"0\";}}}", context: &run) }
    }
    @Test func originalLibertyEligibilityToActualMappingAndIndependentProof() throws {
        var run = try context(limit:100_000_000)
        let compiled = try compile("library(L){cell(IGNORE){dont_use:true;area:0;pin(A){direction:input;}pin(B){direction:input;}pin(Y){direction:output;function:\"A B\";}}cell(MISLEADING_AND){area:2;pin(B){direction:input;}pin(Y){direction:output;function:\"!(A B)\";}pin(A){direction:input;}}}",context:&run)
        let library = try #require(compiled.library)
        #expect(library.cellCount == 1)
        let reference = try LogicEquivalenceContractProbe.bit(context:&run)
        let mapper: any LogicTechnologyMapping = NativeLogicTechnologyMapper()
        let mapped = try mapper.map(reference,library:library,policy:.init(maximumCutInputs:3,maximumCellInputs:6,maximumCutsPerNode:8,firstEntityID:.init(rawValue:10_000)),context:&run)
        #expect(mapped.design.library.source == compiled.source)
        #expect(mapped.statistics.instanceCount == 2)
        #expect(mapped.statistics.area == 4)
        let problem = try LogicEquivalenceContractProbe.problem(.bit(reference),.mapped(mapped.design),inputs:2,context:&run)
        guard case .equivalent(let proof) = try NativeLogicEquivalenceChecker().check(problem,context:&run) else { Issue.record("Liberty mapping was not proved"); return }
        try proof.requireBinding(to:problem)
    }

}
