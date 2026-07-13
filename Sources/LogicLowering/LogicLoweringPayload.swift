import Foundation
import LogicIR
import XcircuitePackage

public struct LogicLoweringPayload: Sendable, Hashable, Codable {
    public var sourceDesignDigest: String?
    public var executionDesign: LogicDesignReference?
    public var loweredSignalCount: Int
    public var loweredNodeCount: Int

    public init(
        sourceDesignDigest: String? = nil,
        executionDesign: LogicDesignReference? = nil,
        loweredSignalCount: Int = 0,
        loweredNodeCount: Int = 0
    ) {
        self.sourceDesignDigest = sourceDesignDigest
        self.executionDesign = executionDesign
        self.loweredSignalCount = loweredSignalCount
        self.loweredNodeCount = loweredNodeCount
    }
}
