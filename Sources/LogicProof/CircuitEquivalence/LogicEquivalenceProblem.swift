import LogicKernelCore
import LogicSimulation

public struct LogicEquivalenceProblem: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        static var payloadByteCount: UInt64 {
            UInt64(MemoryLayout<(LogicBinaryDesign, LogicBinaryDesign, [LogicBitCorrespondence], [LogicBitCorrespondence], [LogicBitCorrespondence], EquivalenceShape, EquivalenceShape)>.stride)
        }
        let reference: LogicBinaryDesign
        let candidate: LogicBinaryDesign
        let inputs: [LogicBitCorrespondence]
        let outputs: [LogicBitCorrespondence]
        let states: [LogicBitCorrespondence]
        let referenceShape: EquivalenceShape
        let candidateShape: EquivalenceShape
        init(reference: LogicBinaryDesign, candidate: LogicBinaryDesign, inputs: consuming [LogicBitCorrespondence],
             outputs: consuming [LogicBitCorrespondence], states: consuming [LogicBitCorrespondence],
             referenceShape: EquivalenceShape, candidateShape: EquivalenceShape) {
            self.reference = reference; self.candidate = candidate; self.inputs = inputs; self.outputs = outputs; self.states = states
            self.referenceShape = referenceShape; self.candidateShape = candidateShape
        }
    }
    internal let storage: Storage
    public var inputBitCount: Int { storage.inputs.count }
    public var outputBitCount: Int { storage.outputs.count }
    public var stateBitCount: Int { storage.states.count }
    public init(reference: LogicBinaryDesign, candidate: LogicBinaryDesign, inputs: consuming [LogicBitCorrespondence],
                outputs: consuming [LogicBitCorrespondence], states: consuming [LogicBitCorrespondence],
                context: inout LogicKernelContext) throws(LogicKernelError) {
        let lhs = try EquivalenceShape.describe(reference, context: &context)
        let rhs = try EquivalenceShape.describe(candidate, context: &context)
        var bytes = Storage.payloadByteCount + UInt64(MemoryLayout<Self>.stride)
        for count in [inputs.count, outputs.count, states.count] {
            let payload = UInt64(count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicBitCorrespondence>.stride))
            let sum = bytes.addingReportingOverflow(payload.partialValue)
            guard !payload.overflow, !sum.overflow else { throw .invalidInput("Correspondence storage overflows") }
            bytes = sum.partialValue
        }
        _ = try context.reserveStorage(byteCount: bytes)
        try Self.validate(inputs, reference: lhs.inputs, candidate: rhs.inputs, context: &context)
        try Self.validate(outputs, reference: lhs.outputs, candidate: rhs.outputs, context: &context)
        try Self.validate(states, reference: lhs.initials.count, candidate: rhs.initials.count, context: &context)
        for index in states.indices {
            let pair = states[index]
            try context.charge(.workUnits)
            guard lhs.initials[pair.reference] == rhs.initials[pair.candidate] else { throw .invalidInput("Corresponding initial-state ranges differ") }
            guard lhs.kinds[pair.reference] == rhs.kinds[pair.candidate] else { throw .unsupported("State-preserving proof requires corresponding state kinds and clock edges") }
        }
        storage = .init(reference: reference, candidate: candidate, inputs: inputs, outputs: outputs, states: states, referenceShape: lhs, candidateShape: rhs)
    }
    private static func validate(_ pairs: borrowing [LogicBitCorrespondence], reference: Int, candidate: Int,
                                 context: inout LogicKernelContext) throws(LogicKernelError) {
        guard pairs.count == reference, pairs.count == candidate else { throw .invalidInput("Correspondence must cover both complete interfaces") }
        let payload = UInt64(reference).multipliedReportingOverflow(by: 2)
        guard !payload.overflow else { throw .invalidInput("Correspondence validation capacity overflows") }
        let reservation = try context.reserveStorage(byteCount: payload.partialValue)
        do throws(LogicKernelError) {
            var lhs = [Bool](repeating: false, count: reference); var rhs = lhs
            for index in pairs.indices {
                let pair = pairs[index]
                try context.charge(.workUnits)
                guard pair.reference < reference, pair.candidate < candidate,
                      !lhs[pair.reference], !rhs[pair.candidate] else { throw .invalidInput("Correspondence is not a total bijection") }
                lhs[pair.reference] = true; rhs[pair.candidate] = true
            }
        } catch { try context.releaseStorage(reservation); throw error }
        try context.releaseStorage(reservation)
    }
}
