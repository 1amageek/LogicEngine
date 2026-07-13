import Foundation

public struct LogicVector: Sendable, Hashable, Codable, CustomStringConvertible {
    public enum Comparison: String, Sendable, Hashable, Codable {
        case lessThan
        case lessEqual
        case greaterThan
        case greaterEqual
    }

    public var bits: [LogicValue]

    private init(validatedBits: [LogicValue]) {
        self.bits = validatedBits
    }

    public init(bits: [LogicValue]) throws {
        guard !bits.isEmpty else {
            throw LogicExecutionError.emptyLogicVector
        }
        self.bits = bits
    }

    public init(string: String) throws {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst(string.hasPrefix("0b") || string.hasPrefix("0B") ? 2 : 0)
        guard !normalized.isEmpty else {
            throw LogicExecutionError.emptyLogicVector
        }
        var parsed: [LogicValue] = []
        parsed.reserveCapacity(normalized.count)
        for character in normalized {
            parsed.append(try LogicValue(character: character))
        }
        self.bits = parsed
    }

    public init(_ value: LogicValue) {
        self.bits = [value]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(string: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func unknown(width: Int) throws -> LogicVector {
        guard width > 0 else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        return LogicVector(validatedBits: Array(repeating: .unknown, count: width))
    }

    public static func zero(width: Int) throws -> LogicVector {
        guard width > 0 else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        return LogicVector(validatedBits: Array(repeating: .zero, count: width))
    }

    public var width: Int { bits.count }

    public var description: String {
        bits.map(\.rawValue).joined()
    }

    public subscript(index: Int) -> LogicValue {
        bits[index]
    }

    public func broadcast(to width: Int) throws -> LogicVector {
        guard width > 0 else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        if self.width == width {
            return self
        }
        guard self.width == 1 else {
            throw LogicExecutionError.vectorWidthMismatch(expected: width, actual: self.width)
        }
        return LogicVector(validatedBits: Array(repeating: bits[0], count: width))
    }

    public func inverted() -> LogicVector {
        LogicVector(validatedBits: bits.map(\.inverted))
    }

    public static func concatenated(_ values: [LogicVector]) throws -> LogicVector {
        guard !values.isEmpty else {
            throw LogicExecutionError.missingNodeInput
        }
        return try LogicVector(bits: values.flatMap(\.bits))
    }

    public static func caseEqual(_ lhs: LogicVector, _ rhs: LogicVector) throws -> LogicVector {
        guard lhs.width == rhs.width else {
            throw LogicExecutionError.vectorWidthMismatch(expected: lhs.width, actual: rhs.width)
        }
        return LogicVector(lhs.bits == rhs.bits ? .one : .zero)
    }

    public static func caseNotEqual(_ lhs: LogicVector, _ rhs: LogicVector) throws -> LogicVector {
        try caseEqual(lhs, rhs).inverted()
    }

    public static func logicallyEqual(_ lhs: LogicVector, _ rhs: LogicVector) throws -> LogicVector {
        guard lhs.width == rhs.width else {
            throw LogicExecutionError.vectorWidthMismatch(expected: lhs.width, actual: rhs.width)
        }
        guard lhs.bits.allSatisfy(\.isKnown), rhs.bits.allSatisfy(\.isKnown) else {
            return try .unknown(width: 1)
        }
        return LogicVector(lhs.bits == rhs.bits ? .one : .zero)
    }

    public static func logicallyNotEqual(_ lhs: LogicVector, _ rhs: LogicVector) throws -> LogicVector {
        try logicallyEqual(lhs, rhs).inverted()
    }

    public static func compared(
        _ lhs: LogicVector,
        _ rhs: LogicVector,
        relation: Comparison,
        signed: Bool
    ) throws -> LogicVector {
        guard lhs.width == rhs.width else {
            throw LogicExecutionError.vectorWidthMismatch(expected: lhs.width, actual: rhs.width)
        }
        let result: Bool
        if signed {
            guard let leftBits = lhs.knownSignedBitPattern(width: lhs.width),
                  let rightBits = rhs.knownSignedBitPattern(width: rhs.width) else {
                return try .unknown(width: 1)
            }
            let left = Int64(bitPattern: leftBits)
            let right = Int64(bitPattern: rightBits)
            switch relation {
            case .lessThan: result = left < right
            case .lessEqual: result = left <= right
            case .greaterThan: result = left > right
            case .greaterEqual: result = left >= right
            }
        } else {
            guard let left = lhs.knownUnsignedValue,
                  let right = rhs.knownUnsignedValue else {
                return try .unknown(width: 1)
            }
            switch relation {
            case .lessThan: result = left < right
            case .lessEqual: result = left <= right
            case .greaterThan: result = left > right
            case .greaterEqual: result = left >= right
            }
        }
        return LogicVector(result ? .one : .zero)
    }

    public static func logicalAnd(_ lhs: LogicVector, _ rhs: LogicVector) -> LogicVector {
        LogicVector(logicalValue: logicalTruth(of: lhs).logicalAnd(logicalTruth(of: rhs)))
    }

    public static func logicalOr(_ lhs: LogicVector, _ rhs: LogicVector) -> LogicVector {
        LogicVector(logicalValue: logicalTruth(of: lhs).logicalOr(logicalTruth(of: rhs)))
    }

    public static func logicalNot(_ value: LogicVector) -> LogicVector {
        LogicVector(logicalValue: logicalTruth(of: value).logicalNot)
    }

    public static func added(_ lhs: LogicVector, _ rhs: LogicVector, width: Int) throws -> LogicVector {
        try arithmetic(lhs, rhs, width: width) { $0 &+ $1 }
    }

    public static func signedAdded(_ lhs: LogicVector, _ rhs: LogicVector, width: Int) throws -> LogicVector {
        try arithmetic(lhs, rhs, width: width, signed: true) { $0 &+ $1 }
    }

    public static func subtracted(_ lhs: LogicVector, _ rhs: LogicVector, width: Int) throws -> LogicVector {
        try arithmetic(lhs, rhs, width: width) { $0 &- $1 }
    }

    public static func signedSubtracted(_ lhs: LogicVector, _ rhs: LogicVector, width: Int) throws -> LogicVector {
        try arithmetic(lhs, rhs, width: width, signed: true) { $0 &- $1 }
    }

    public static func multiplied(_ lhs: LogicVector, _ rhs: LogicVector, width: Int) throws -> LogicVector {
        try arithmetic(lhs, rhs, width: width) { $0 &* $1 }
    }

    public static func divided(
        _ lhs: LogicVector,
        _ rhs: LogicVector,
        width: Int,
        signed: Bool = false
    ) throws -> LogicVector {
        guard width > 0, width <= UInt64.bitWidth else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        if signed {
            guard let leftBits = lhs.knownSignedBitPattern(width: width),
                  let rightBits = rhs.knownSignedBitPattern(width: width) else {
                return try .unknown(width: width)
            }
            let signedLeft = Int64(bitPattern: leftBits)
            let signedRight = Int64(bitPattern: rightBits)
            if signedRight == 0 {
                return try .unknown(width: width)
            }
            let quotient: Int64
            if signedLeft == Int64.min, signedRight == -1 {
                quotient = Int64.min
            } else {
                quotient = signedLeft / signedRight
            }
            return try bitPattern(UInt64(bitPattern: quotient), width: width)
        }
        guard let left = lhs.knownUnsignedValue,
              let right = rhs.knownUnsignedValue,
              right != 0 else {
            return try .unknown(width: width)
        }
        return try bitPattern(left / right, width: width)
    }

    public static func modulo(
        _ lhs: LogicVector,
        _ rhs: LogicVector,
        width: Int,
        signed: Bool = false
    ) throws -> LogicVector {
        guard width > 0, width <= UInt64.bitWidth else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        if signed {
            guard let leftBits = lhs.knownSignedBitPattern(width: width),
                  let rightBits = rhs.knownSignedBitPattern(width: width) else {
                return try .unknown(width: width)
            }
            let signedLeft = Int64(bitPattern: leftBits)
            let signedRight = Int64(bitPattern: rightBits)
            if signedRight == 0 {
                return try .unknown(width: width)
            }
            let remainder: Int64
            if signedLeft == Int64.min, signedRight == -1 {
                remainder = 0
            } else {
                remainder = signedLeft % signedRight
            }
            return try bitPattern(UInt64(bitPattern: remainder), width: width)
        }
        guard let left = lhs.knownUnsignedValue,
              let right = rhs.knownUnsignedValue,
              right != 0 else {
            return try .unknown(width: width)
        }
        return try bitPattern(left % right, width: width)
    }

    public static func signedMultiplied(_ lhs: LogicVector, _ rhs: LogicVector, width: Int) throws -> LogicVector {
        try arithmetic(lhs, rhs, width: width, signed: true) { $0 &* $1 }
    }

    public static func shiftedLeft(_ value: LogicVector, by amount: LogicVector, width: Int) throws -> LogicVector {
        try shift(value, amount: amount, width: width) { value, count in value &<< count }
    }

    public static func shiftedRight(_ value: LogicVector, by amount: LogicVector, width: Int) throws -> LogicVector {
        try shift(value, amount: amount, width: width) { value, count in value &>> count }
    }

    public static func arithmeticShiftedRight(
        _ value: LogicVector,
        by amount: LogicVector,
        width: Int
    ) throws -> LogicVector {
        guard width > 0, width <= UInt64.bitWidth else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        guard let base = value.knownSignedInt64BitPattern,
              let count = amount.knownUnsignedValue else {
            return try .unknown(width: width)
        }
        let shifted: UInt64
        if count >= UInt64(width) {
            shifted = Int64(bitPattern: base) < 0 ? UInt64.max : 0
        } else {
            shifted = UInt64(bitPattern: Int64(bitPattern: base) >> Int64(count))
        }
        return try bitPattern(shifted, width: width)
    }

    private static func arithmetic(
        _ lhs: LogicVector,
        _ rhs: LogicVector,
        width: Int,
        signed: Bool = false,
        operation: (UInt64, UInt64) -> UInt64
    ) throws -> LogicVector {
        guard width > 0, width <= UInt64.bitWidth else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        guard lhs.width <= UInt64.bitWidth, rhs.width <= UInt64.bitWidth else {
            throw LogicExecutionError.invalidDesign("arithmetic width exceeds the native profile")
        }
        let left = signed
            ? lhs.knownSignedBitPattern(width: width)
            : lhs.knownUnsignedValue
        let right = signed
            ? rhs.knownSignedBitPattern(width: width)
            : rhs.knownUnsignedValue
        guard let left, let right else {
            return try .unknown(width: width)
        }
        return try bitPattern(operation(left, right), width: width)
    }

    private static func shift(
        _ value: LogicVector,
        amount: LogicVector,
        width: Int,
        operation: (UInt64, UInt64) -> UInt64
    ) throws -> LogicVector {
        guard width > 0, width <= UInt64.bitWidth else {
            throw LogicExecutionError.invalidSignalWidth(width)
        }
        guard let base = value.knownUnsignedValue, let count = amount.knownUnsignedValue else {
            return try .unknown(width: width)
        }
        guard count < UInt64(UInt64.bitWidth) else {
            return try .zero(width: width)
        }
        let mask = bitMask(width: width)
        return try bitPattern(operation(base & mask, count) & mask, width: width)
    }

    private static func unsigned(_ value: UInt64, width: Int) throws -> LogicVector {
        let binary = String(value, radix: 2)
        guard binary.count <= width else {
            throw LogicExecutionError.invalidDesign("unsigned arithmetic result exceeds the destination width")
        }
        return try LogicVector(string: String(repeating: "0", count: width - binary.count) + binary)
    }

    private static func bitPattern(_ value: UInt64, width: Int) throws -> LogicVector {
        let masked = value & bitMask(width: width)
        return try unsigned(masked, width: width)
    }

    private static func bitMask(width: Int) -> UInt64 {
        width == UInt64.bitWidth
            ? UInt64.max
            : (UInt64(1) &<< UInt64(width)) &- 1
    }

    private var knownUnsignedValue: UInt64? {
        guard bits.count <= UInt64.bitWidth, bits.allSatisfy(\.isKnown) else { return nil }
        return bits.reduce(UInt64(0)) { value, bit in
            (value &<< 1) | (bit == .one ? 1 : 0)
        }
    }

    private func knownSignedBitPattern(width: Int) -> UInt64? {
        guard let value = knownUnsignedValue else { return nil }
        let sourceMask = Self.bitMask(width: self.width)
        let destinationMask = Self.bitMask(width: width)
        let truncated = value & sourceMask
        guard bits.first == .one else {
            return truncated & destinationMask
        }
        return (truncated | ~sourceMask) & destinationMask
    }

    private var knownSignedInt64BitPattern: UInt64? {
        guard let value = knownUnsignedValue else { return nil }
        let sourceMask = Self.bitMask(width: width)
        let truncated = value & sourceMask
        return bits.first == .one ? truncated | ~sourceMask : truncated
    }

    public func sliced(
        sourceMSB: Int,
        sourceLSB: Int,
        selectionMSB: Int,
        selectionLSB: Int
    ) throws -> LogicVector {
        let sourceLowerBound = min(sourceMSB, sourceLSB)
        let sourceUpperBound = max(sourceMSB, sourceLSB)
        let selectionLowerBound = min(selectionMSB, selectionLSB)
        let selectionUpperBound = max(selectionMSB, selectionLSB)
        guard selectionLowerBound >= sourceLowerBound,
              selectionUpperBound <= sourceUpperBound else {
            throw LogicExecutionError.invalidDesign("slice selection is outside the source range")
        }

        let selectionStep = selectionMSB >= selectionLSB ? -1 : 1
        let selectionIndices = stride(
            from: selectionMSB,
            through: selectionLSB,
            by: selectionStep
        )
        let sourceIsDescending = sourceMSB >= sourceLSB
        let selectedBits = try selectionIndices.map { index in
            let position = sourceIsDescending ? sourceMSB - index : index - sourceMSB
            guard position >= 0, position < bits.count else {
                throw LogicExecutionError.invalidDesign("slice index is outside the source vector")
            }
            return bits[position]
        }
        return try LogicVector(bits: selectedBits)
    }

    public static func and(_ values: [LogicVector], width: Int) throws -> LogicVector {
        try reduce(values, width: width) { bits in
            if bits.contains(.zero) { return .zero }
            if bits.allSatisfy({ $0 == .one }) { return .one }
            return .unknown
        }
    }

    public static func or(_ values: [LogicVector], width: Int) throws -> LogicVector {
        try reduce(values, width: width) { bits in
            if bits.contains(.one) { return .one }
            if bits.allSatisfy({ $0 == .zero }) { return .zero }
            return .unknown
        }
    }

    public static func xor(_ values: [LogicVector], width: Int) throws -> LogicVector {
        try reduce(values, width: width) { bits in
            guard bits.allSatisfy(\.isKnown) else { return .unknown }
            return bits.filter { $0 == .one }.count.isMultiple(of: 2) ? .zero : .one
        }
    }

    public static func merge(_ lhs: LogicVector, _ rhs: LogicVector) throws -> LogicVector {
        let width = max(lhs.width, rhs.width)
        let left = try lhs.broadcast(to: width)
        let right = try rhs.broadcast(to: width)
        return LogicVector(validatedBits: zip(left.bits, right.bits).map { $0 == $1 ? $0 : .unknown })
    }

    private static func reduce(
        _ values: [LogicVector],
        width: Int,
        operation: ([LogicValue]) -> LogicValue
    ) throws -> LogicVector {
        guard !values.isEmpty else {
            throw LogicExecutionError.missingNodeInput
        }
        let normalized = try values.map { try $0.broadcast(to: width) }
        let result = (0..<width).map { index in
            operation(normalized.map { $0.bits[index] })
        }
        return LogicVector(validatedBits: result)
    }

    private init(logicalValue: LogicValue) {
        self.bits = [logicalValue]
    }

    private static func logicalTruth(of vector: LogicVector) -> LogicValue {
        if vector.bits.contains(.one) {
            return .one
        }
        if vector.bits.contains(where: { !$0.isKnown }) {
            return .unknown
        }
        return .zero
    }
}

private extension LogicValue {
    var logicalNot: LogicValue {
        switch self {
        case .zero: return .one
        case .one: return .zero
        case .unknown, .highImpedance: return .unknown
        }
    }

    func logicalAnd(_ other: LogicValue) -> LogicValue {
        if self == .zero || other == .zero {
            return .zero
        }
        if self == .one && other == .one {
            return .one
        }
        return .unknown
    }

    func logicalOr(_ other: LogicValue) -> LogicValue {
        if self == .one || other == .one {
            return .one
        }
        if self == .zero && other == .zero {
            return .zero
        }
        return .unknown
    }
}
