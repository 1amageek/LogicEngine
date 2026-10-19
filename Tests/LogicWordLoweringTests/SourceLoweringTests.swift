import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import SystemVerilogFrontend
import LogicLowering
import LogicWordLoweringProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct SourceLoweringTests {
    @available(macOS 26.0, *)
    private func source(_ texts: [String], context: inout LogicKernelContext) throws -> LogicSourceBundle {
        var documents: [LogicSourceDocument] = []
        for index in texts.indices {
            let bytes = Array(texts[index].utf8)
            let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
                hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
            documents.append(try LogicSourceDocument(logicalName: "s\(index).sv", artifactID: artifact, bytes: bytes, context: &context))
        }
        return try LogicSourceBundle(documents: documents, context: &context)
    }
    @available(macOS 26.0, *)
    private func compile(_ texts: [String], context: inout LogicKernelContext) throws -> BitLogicDesign {
        let bundle = try source(texts, context: &context)
        let frontend: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
        let roots = texts.indices.map { "s\($0).sv" }
        let rtl = try frontend.elaborate(bundle, options: SourceLoweringContractProbe.options(roots), context: &context)
        let identities = rtl.withProgram { _, _, _, _, _, ports, _ in
            var ids: [DesignEntityID] = []; for index in ports.indices { ids.append(ports[index].id) }; return ids
        }
        let wordKernel: any LogicWordLowering = NativeLogicWordLowering()
        let word = try wordKernel.lower(rtl, context: &context)
        #expect(word.withTables { _, _, ports, _, _ in
            guard ports.count == identities.count else { return false }
            for index in ports.indices where ports[index].id != identities[index] { return false }; return true
        })
        let bitKernel: any LogicBitLowering = NativeLogicBitLowering()
        let bit = try bitKernel.lower(word, context: &context)
        #expect(bit.withTables { _, _, ports, _, _, _ in
            guard ports.count == identities.count else { return false }
            for index in ports.indices where ports[index].id != identities[index] { return false }; return true
        })
        return bit
    }
    @Test func eightBitANDHasEightActualBitGatesAndAllInputPairsAgree() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try RTLFixture.context()
        let graph = try compile(["module p(input [7:0] a,b,output [7:0] y);assign y=a&b;endmodule"], context: &run)
        let count = graph.withTables { nodes, _, _, _, _, _ in
            var count = 0; for index in nodes.indices { if case .and = nodes[index].operation { count += 1 } }; return count
        }
        #expect(count == 8)
        for a in 0..<256 { for b in 0..<256 {
            #expect(try SourceLoweringContractProbe.observe(graph, inputs: [UInt64(a), UInt64(b)]).outputs[0] == UInt64(a & b))
        } }
    }
    @Test func arithmeticSignedComparisonAndShiftMatchIndependentSmallIntegers() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try RTLFixture.context()
        let graph = try compile(["module p(input signed [3:0] a,b,output signed [4:0] sum,output [7:0] product,output less,output [3:0] shifted);assign sum=a+b;assign product=a*b;assign less=a<b;assign shifted=a>>>b;endmodule"], context: &run)
        for a in 0..<16 { for b in 0..<16 {
            let signedA = a >= 8 ? a-16 : a; let signedB = b >= 8 ? b-16 : b
            let output = try SourceLoweringContractProbe.observe(graph, inputs: [UInt64(a), UInt64(b)]).outputs
            #expect(output[0] == UInt64((signedA+signedB) & 31))
            #expect(output[1] == UInt64((signedA*signedB) & 255))
            #expect(output[2] == (signedA < signedB ? 1 : 0))
            #expect(output[3] == UInt64((signedA >> b) & 15))
        } }
    }
    @Test func hierarchyStaticLoopsAtomicWritesCaseAndRenamingRetainFunction() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for name in ["a_first", "z_last"] {
            var run = try RTLFixture.context()
            let graph = try compile([
                "`define W 4\nmodule p(input [`W-1:0] a,output [`W-1:0] y);child #(.W(`W)) \(name)(.a(a),.y(y));endmodule",
                "module child #(parameter W=1)(input [W-1:0] a,output logic [W-1:0] y);if(W==4)begin:g always_comb begin y=0;for(int i=0;i<W;i++)y[i]=a[i];{y[3:2],y[1:0]}={y[1:0],y[3:2]};case(a)4'hf:y=0;default:;endcase end end endmodule"], context: &run)
            for a in 0..<16 {
                #expect(try SourceLoweringContractProbe.observe(graph, inputs: [UInt64(a)]).outputs[0] == UInt64(a == 15 ? 0 : ((a & 3) << 2) | (a >> 2)))
            }
        }
    }
    @Test func variableReadAndSampledVariableWriteHaveBinaryInRangeMeaning() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try RTLFixture.context()
        let read = try compile(["module p(input [3:0] a,input [1:0] i,output y);assign y=a[i];endmodule"], context: &run)
        let write = try compile(["module p(input [3:0] a,output logic [3:0] y,output logic [1:0] i);always_comb begin y=a;i=0;{i,y[i]}=3'b101;end endmodule"], context: &run)
        for a in 0..<16 {
            for i in 0..<4 {
                #expect(try SourceLoweringContractProbe.observe(read, inputs: [UInt64(a), UInt64(i)]).outputs[0] == UInt64((a >> i) & 1))
            }
            let output = try SourceLoweringContractProbe.observe(write, inputs: [UInt64(a)]).outputs
            #expect(output[0] == UInt64(a | 1)); #expect(output[1] == 2)
        }
    }
    @Test func sourceFFRetainsClockResetEnableStateAndNextRelation() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try RTLFixture.context()
        let graph = try compile(["module p(input clk,rst_n,en,input [3:0] d,output logic [3:0] q);always_ff @(negedge rst_n or posedge clk)if(!rst_n)q<=0;else if(en)q<=d;endmodule"], context: &run)
        graph.withTables { _, _, ports, bindings, states, _ in
            #expect(states.count == 4)
            for index in states.indices {
                guard case .flipFlop(let clock, .rising, _, let reset?) = states[index].control else { Issue.record("Lost FF/reset"); continue }
                #expect(clock == bindings[ports[0].bits.lowerBound]); #expect(!reset.activeHigh)
                #expect(!reset.value); #expect(states[index].initialValue == nil)
            }
        }
        for old in 0..<16 { for d in 0..<16 { for en in 0..<2 { for reset in 0..<2 {
            let next = try SourceLoweringContractProbe.observe(graph, inputs: [0, UInt64(reset), UInt64(en), UInt64(d)], state: UInt64(old)).next
            #expect(next == UInt64(reset == 0 ? 0 : en == 1 ? d : old))
        } } } }
    }
    @Test func explicitAndInferredLatchProfilesRetainTransparentAndHoldRelations() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for process in ["always_latch", "always @*"] {
            var run = try RTLFixture.context()
            let graph = try compile(["module p(input gate_n,input [3:0] d,output logic [3:0] q);\(process) if(!gate_n)q=d;endmodule"], context: &run)
            graph.withTables { _, _, _, _, states, _ in
                #expect(states.count == 4); for index in states.indices { #expect(states[index].initialValue == nil) }
            }
            for old in 0..<16 { for d in 0..<16 { for gate in 0..<2 {
                #expect(try SourceLoweringContractProbe.observe(graph, inputs: [UInt64(gate), UInt64(d)], state: UInt64(old)).next == UInt64(gate == 0 ? d : old))
            } } }
        }
    }
    @Test func unknownSelectionInitialStorageRacesAndIncompleteAssignmentsAreRefused() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for text in [
            "module p(input [3:0] a,input signed [1:0] i,output y);assign y=a[i];endmodule",
            "module p(input a,output logic y);always_comb if(a)y=1;endmodule",
            "module p(output logic y);logic x;assign y=x;endmodule",
            "module p(input c,d,output logic q,r);always_ff @(posedge c)q=d;always_ff @(posedge c)r=q;endmodule",
            "module p(output y);assign y=1'bx;endmodule"] {
            var run = try RTLFixture.context()
            #expect(throws: LogicKernelError.self) { try compile([text], context: &run) }
        }
    }
    @Test func cumulativePipelineWorkCancellationAndSharedPortableProbeAreObserved() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var setup = try RTLFixture.context()
        let bundle = try source(["module p(input [3:0] a,b,output [3:0] y);assign y=a+b;endmodule"], context: &setup)
        let options = try SourceLoweringContractProbe.options(["s0.sv"])
        var measured = try RTLFixture.context()
        let rtl = try NativeSystemVerilogElaborator().elaborate(bundle, options: options, context: &measured)
        let word = try NativeLogicWordLowering().lower(rtl, context: &measured)
        _ = try NativeLogicBitLowering().lower(word, context: &measured)
        var bounded = try RTLFixture.context(work: measured.usage[.workUnits]-1)
        #expect(throws: LogicKernelError.self) {
            let rtl = try NativeSystemVerilogElaborator().elaborate(bundle, options: options, context: &bounded)
            let word = try NativeLogicWordLowering().lower(rtl, context: &bounded)
            return try NativeLogicBitLowering().lower(word, context: &bounded)
        }
        var cancelled = try RTLFixture.context(control: RTLFixture.Control(.cancelled))
        #expect(throws: LogicKernelError.self) {
            try NativeLogicWordLowering().lower(rtl, context: &cancelled)
        }
        #expect(cancelled.usage[.managedStorageBytes] == 0)
        try SourceLoweringContractProbe.exercise()
    }
}
