import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicSynthesis
import LogicProofProbeSupport
import LogicLowering
import SystemVerilogFrontend
import LogicWordLoweringProbeSupport

extension TechnologyMappingContractProbe {
    public static func sourceStateIntegration() throws(LogicKernelError) {
        var context = try LogicProofContractProbe.context()
        for latch in [false,true] {
            let text = latch ? "module p(input g,d,output logic q);always_latch if(!g)q=d;endmodule" : "module p(input clk,rn,en,input [1:0] d,output logic [1:0] q);always_ff @(posedge clk or negedge rn) if(!rn) q<=2'b10;else if(en) q<=d;endmodule"
            let hash = latch ? "edddc64f4eb21f304ede4f3a3b93af98515831cdfe8ba63ebde9ce5e9c220edc" : "f8ab0cffcdc1376e4c78c3133852cf5fa90f9b10d447aac45b17f78e7881bb5b"
            let bytes = Array(text.utf8); let identity: ArtifactID
            do { identity = try .init(digest:.init(algorithm:.sha256,hexadecimalValue:hash),byteCount:UInt64(bytes.count)) }
            catch { throw .invalidInput("Invalid state source fixture") }
            let doc = try LogicSourceDocument(logicalName:"p.sv",artifactID:identity,bytes:bytes,context:&context)
            let bundle = try LogicSourceBundle(documents:[doc],context:&context)
            let frontend: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
            let rtl = try frontend.elaborate(bundle,options:SourceLoweringContractProbe.options(["p.sv"]),context:&context)
            let word = try NativeLogicWordLowering().lower(rtl,context:&context)
            let bit = try NativeLogicBitLowering().lower(word,context:&context)
            var cells = [try cell(.nand,id:100,area:1,context:&context)]
            cells.append(try sequentialCell(latch:latch,high:!latch,asynchronous:!latch,context:&context))
            if !latch { cells.append(try sequentialCell(id:2000,asynchronous:true,resetValue:true,context:&context)) }
            let library = try Self.library(cells,context:&context)
            let result = try verify(bit,library:library,context:&context)
            guard result.design.stateCount == (latch ? 1 : 2) else { throw .invalidModel("Source state bits were lost") }
            try result.design.withTables { _, instances, _, _, _, _ throws(LogicKernelError) in
                for i in instances.indices where instances[i].stateID != nil {
                    guard instances[i].initialValue == nil else { throw .invalidModel("Unspecified source state was changed") }
                }
            }
        }
    }
}
