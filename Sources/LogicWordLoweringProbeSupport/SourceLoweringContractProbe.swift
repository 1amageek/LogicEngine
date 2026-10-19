import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicLowering
import SystemVerilogFrontend

public enum SourceLoweringContractProbe {
    @available(macOS 26.0, *)
    public nonisolated static func exercise() throws(LogicKernelError) {
        let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(100_000_000)) }))
        var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
        var documents: [LogicSourceDocument] = []
        do {
            let bytes = Array("`define W 8\nmodule p(input [`W-1:0] a,b,output [`W-1:0] y);assign y=a&b;endmodule".utf8)
            let artifact: ArtifactID
            do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
                hexadecimalValue: "bab4078e6cce9bce3b7debbfd9da8c5aa5f5cc9aa41d8c84dc45d466f87a3c22"), byteCount: UInt64(bytes.count)) }
            catch { throw .invalidModel("Source lowering fixture identity is invalid") }
            documents.append(try LogicSourceDocument(logicalName: "and.sv", artifactID: artifact, bytes: bytes, context: &context))
        }
        do {
            let bytes = Array("module p(input clk,rst_n,en,input [3:0] d,output logic [3:0] q);always_ff @(posedge clk or negedge rst_n) if(!rst_n)q<=0;else if(en)q<=d;endmodule".utf8)
            let artifact: ArtifactID
            do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
                hexadecimalValue: "3f1cba96459826893e3557e8db4f25afb093192c3117589dcc881bb86e656b0e"), byteCount: UInt64(bytes.count)) }
            catch { throw .invalidModel("Source lowering fixture identity is invalid") }
            documents.append(try LogicSourceDocument(logicalName: "ff.sv", artifactID: artifact, bytes: bytes, context: &context))
        }
        do {
            let bytes = Array("module p(input gate_n,input [3:0] d,output logic [3:0] q);always_latch if(!gate_n)q=d;endmodule".utf8)
            let artifact: ArtifactID
            do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
                hexadecimalValue: "52544cb5ff0fe3d72efb7418c5b1c2c26cdb4ac947d8e951b764b7aabe58b1f9"), byteCount: UInt64(bytes.count)) }
            catch { throw .invalidModel("Source lowering fixture identity is invalid") }
            documents.append(try LogicSourceDocument(logicalName: "latch.sv", artifactID: artifact, bytes: bytes, context: &context))
        }
        do {
            let bytes = Array("module p(output y);assign y=1'bx;endmodule".utf8)
            let artifact: ArtifactID
            do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
                hexadecimalValue: "2082cb0a46e0a0fac365c92bb06e649bedca54b01d3d4ddb8f1e9804ac434ffe"), byteCount: UInt64(bytes.count)) }
            catch { throw .invalidModel("Source lowering fixture identity is invalid") }
            documents.append(try LogicSourceDocument(logicalName: "bad.sv", artifactID: artifact, bytes: bytes, context: &context))
        }
        let bundle = try LogicSourceBundle(documents: documents, context: &context)
        let frontend: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
        let wordKernel: any LogicWordLowering = NativeLogicWordLowering()
        let bitKernel: any LogicBitLowering = NativeLogicBitLowering()
        for name in ["and.sv", "ff.sv", "latch.sv"] {
            let rtl = try frontend.elaborate(bundle, options: options([name]), context: &context)
            let identities = rtl.withProgram { _, _, _, _, _, ports, _ in
                var ids: [DesignEntityID] = []; for index in ports.indices { ids.append(ports[index].id) }; return ids
            }
            let word = try wordKernel.lower(rtl, context: &context)
            let bit = try bitKernel.lower(word, context: &context)
            let matches = bit.withTables { _, _, ports, _, _, _ in
                guard ports.count == identities.count else { return false }
                for index in ports.indices where ports[index].id != identities[index] { return false }; return true
            }
            guard matches else { throw .invalidModel("Source lowering changed canonical port identities") }
            if name == "and.sv" {
                let count = bit.withTables { nodes, _, _, _, states, _ in
                    var count = 0
                    for index in nodes.indices { if case .and = nodes[index].operation { count += 1 } }
                    return states.isEmpty ? count : -1
                }
                guard count == 8 else { throw .invalidModel("Eight-bit AND did not produce eight independent gates") }
                for a in 0..<256 {
                    let b = 255-a
                    guard try observe(bit, inputs: [UInt64(a), UInt64(b)]).outputs[0] == UInt64(a & b) else {
                        throw .invalidModel("Published bit gates changed eight-bit AND")
                    }
                }
            } else {
                guard bit.withTables({ _, _, _, _, states, _ in states.count == 4 }) else {
                    throw .invalidModel("Source lowering changed retained state-bit count")
                }
                for old in 0..<16 { for data in 0..<16 { for control in 0..<2 {
                    if name == "ff.sv" {
                        let observed = try observe(bit, inputs: [0, 1, UInt64(control), UInt64(data)], state: UInt64(old))
                        guard observed.next == UInt64(control == 1 ? data : old) else { throw .invalidModel("FF enable/hold relation changed") }
                        guard try observe(bit, inputs: [0, 0, UInt64(control), UInt64(data)], state: UInt64(old)).next == 0 else {
                            throw .invalidModel("FF asynchronous reset relation changed")
                        }
                    } else {
                        guard try observe(bit, inputs: [UInt64(control), UInt64(data)], state: UInt64(old)).next == UInt64(control == 0 ? data : old) else {
                            throw .invalidModel("Latch transparent/hold relation changed")
                        }
                    }
                } } }
            }
        }
        print("SOURCE_LOWERING_USAGE work=\(context.usage[.workUnits]) peakManagedPayload=\(context.usage.peakManagedStorageBytes)")
        do throws(LogicKernelError) {
            _ = try frontend.elaborate(bundle, options: options(["bad.sv"]), context: &context)
            throw .invalidModel("Source-to-bit path accepted synthesis X")
        } catch {
            guard case .sourceFailure(let code, _, _) = error, code.rawValue == "SV_SYNTHESIS_XZ_LITERAL" else { throw error }
        }
    }

    public static func options(_ roots: consuming [String]) throws(LogicKernelError) -> SystemVerilogElaborationOptions {
        try SystemVerilogElaborationOptions(roots: roots, top: "p", maximumTokens: 4000,
            syntax: SystemVerilogSyntaxLimits(nodes: 2000, children: 4000, symbols: 1000, nesting: 60),
            rtl: RTLResolvedCapacity(signals: 100, expressions: 2000, operands: 4000, statements: 1000,
                children: 2000, caseItems: 100, caseMatches: 200, ports: 20, processes: 100), maximumNesting: 60)
    }

    // Verification-only binary observation of actual gate functions and the
    // transition relation. Explicit state is required; no event scheduling or
    // initial-zero simulation assumption is introduced by this reference.
    @available(macOS 26.0, *)
    public static func observe(_ graph: borrowing BitLogicDesign, inputs: [UInt64], state: UInt64? = nil)
        throws(LogicKernelError) -> (outputs: [UInt64], next: UInt64) {
        let observation: Result<(outputs: [UInt64], next: UInt64), LogicKernelError> = graph.withTables { (nodes: borrowing Span<BitLogicNode>, operands: borrowing Span<BitNodeIndex>,
            ports: borrowing Span<BitLogicPort>, bindings: borrowing Span<BitNodeIndex>,
            states: borrowing Span<BitLogicState>, order: borrowing Span<BitNodeIndex>) -> Result<(outputs: [UInt64], next: UInt64), LogicKernelError> in
            guard states.count <= 64, states.isEmpty || state != nil else { return .failure(.invalidInput("Reference requires explicit small binary state")) }
            var values = [Bool](repeating: false, count: nodes.count); var input = 0
            for index in ports.indices where ports[index].direction == .input {
                guard ports[index].bits.count <= 64, input < inputs.count else { return .failure(.invalidInput("Reference input is missing or wide")) }
                let value = inputs[input]; input += 1
                for offset in 0..<ports[index].bits.count {
                    values[bindings[ports[index].bits.lowerBound + offset].rawValue] = value & (1 << offset) != 0
                }
            }
            guard input == inputs.count else { return .failure(.invalidInput("Reference input count differs from circuit ports")) }
            for ordinal in order.indices {
                let index = order[ordinal].rawValue; let node = nodes[index]
                func operand(_ offset: Int) -> Bool { values[operands[node.operands.lowerBound + offset].rawValue] }
                switch node.operation {
                case .input: break
                case .state(let bit): values[index] = state! & (1 << bit.rawValue) != 0
                case .constant(let bit): values[index] = bit
                case .buffer: values[index] = operand(0)
                case .invert: values[index] = !operand(0)
                case .and: values[index] = operand(0) && operand(1)
                case .or: values[index] = operand(0) || operand(1)
                case .xor: values[index] = operand(0) != operand(1)
                case .select: values[index] = operand(0) ? operand(1) : operand(2)
                }
            }
            var outputs: [UInt64] = []
            for index in ports.indices where ports[index].direction == .output {
                guard ports[index].bits.count <= 64 else { return .failure(.invalidInput("Reference output is wide")) }
                var value: UInt64 = 0
                for offset in 0..<ports[index].bits.count {
                    if values[bindings[ports[index].bits.lowerBound + offset].rawValue] { value |= 1 << offset }
                }
                outputs.append(value)
            }
            var next = state ?? 0
            for index in states.indices {
                let entry = states[index]; let reset: BitReset?; let update: Bool
                switch entry.control {
                case .flipFlop(_, _, let enable, let selectedReset):
                    update = enable == nil || values[enable!.rawValue]; reset = selectedReset
                case .latch(let gate, let high, let selectedReset):
                    update = values[gate.rawValue] == high; reset = selectedReset
                }
                let value: Bool
                if let reset, values[reset.signal.rawValue] == reset.activeHigh { value = reset.value }
                else { value = update ? values[entry.next.rawValue] : state! & (1 << index) != 0 }
                if value { next |= 1 << index } else { next &= ~(1 << index) }
            }
            return .success((outputs, next))
        }
        return try observation.get()
    }
}
