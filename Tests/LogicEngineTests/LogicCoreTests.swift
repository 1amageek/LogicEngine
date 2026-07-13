import Foundation
import LogicEngineCore
import Testing

@Suite("LogicEngine core")
struct LogicCoreTests {
    @Test("four-state truth tables preserve unknown values")
    func truthTables() throws {
        let zero = try LogicVector(string: "0")
        let one = try LogicVector(string: "1")
        let unknown = try LogicVector(string: "X")
        #expect(try LogicVector.and([zero, unknown], width: 1) == zero)
        #expect(try LogicVector.or([one, unknown], width: 1) == one)
        #expect(try LogicVector.and([one, unknown], width: 1) == unknown)
        #expect(try LogicVector.xor([one, unknown], width: 1) == unknown)
        #expect(try LogicVector.merge(zero, one) == unknown)
    }

    @Test("signed vector arithmetic preserves sign extension and two's-complement results")
    func signedArithmetic() throws {
        let negativeTwo = try LogicVector(string: "1110")
        let positiveOne = try LogicVector(string: "01")
        let three = try LogicVector(string: "0011")
        let negativeOne = try LogicVector(string: "1111")
        let negativeFive = try LogicVector(string: "1011")
        let unknown = try LogicVector(string: "XXXX")

        #expect(try LogicVector.signedAdded(negativeTwo, positiveOne, width: 4) == negativeOne)
        #expect(try LogicVector.signedSubtracted(negativeTwo, three, width: 4) == negativeFive)
        #expect(try LogicVector.signedMultiplied(negativeTwo, positiveOne, width: 4) == negativeTwo)
        #expect(try LogicVector.arithmeticShiftedRight(negativeTwo, by: LogicVector(string: "1"), width: 4) == negativeOne)
        #expect(try LogicVector.signedAdded(negativeTwo, LogicVector(string: "0X"), width: 4) == unknown)
    }

    @Test("vector logical truth values preserve four-state short-circuit semantics")
    func vectorLogicalTruthValues() throws {
        let zero = try LogicVector(string: "00")
        let one = try LogicVector(string: "01")
        let unknown = try LogicVector(string: "0X")
        let high = try LogicVector(string: "Z0")

        #expect(LogicVector.logicalAnd(zero, unknown) == LogicVector(.zero))
        #expect(LogicVector.logicalAnd(one, unknown) == LogicVector(.unknown))
        #expect(LogicVector.logicalOr(zero, unknown) == LogicVector(.unknown))
        #expect(LogicVector.logicalOr(one, high) == LogicVector(.one))
        #expect(LogicVector.logicalNot(zero) == LogicVector(.one))
        #expect(LogicVector.logicalNot(one) == LogicVector(.zero))
        #expect(LogicVector.logicalNot(high) == LogicVector(.unknown))
    }

    @Test("design and stimulus schemas round-trip as compact JSON values")
    func schemaRoundTrip() throws {
        let vector = try LogicVector(string: "01XZ")
        let design = LogicDesignDocument(
            topDesignName: "round_trip",
            ports: [LogicPort(name: "a", direction: .input, width: 1)],
            signals: [LogicSignal(name: "a", width: 1)],
            nodes: []
        )
        let stimulus = LogicStimulusDocument(
            events: [LogicStimulusEvent(time: 0, assignments: ["a": vector])]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(stimulus)
        let decoded = try JSONDecoder().decode(LogicStimulusDocument.self, from: data)
        #expect(decoded == stimulus)
        #expect(try JSONDecoder().decode(LogicDesignDocument.self, from: encoder.encode(design)) == design)
    }
}
