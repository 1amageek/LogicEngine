import Foundation
import CircuiteFoundation
import LogicIR
import LogicEngineCore

public struct LogicLoweringPayload: Sendable, Hashable, Codable {
    public var sourceDesignDigest: String?
    public var executionDesign: LogicFoundationDesignReference?
    public var loweredSignalCount: Int
    public var loweredNodeCount: Int

    public init(
        sourceDesignDigest: String? = nil,
        executionDesign: LogicFoundationDesignReference? = nil,
        loweredSignalCount: Int = 0,
        loweredNodeCount: Int = 0
    ) {
        self.sourceDesignDigest = sourceDesignDigest
        self.executionDesign = executionDesign
        self.loweredSignalCount = loweredSignalCount
        self.loweredNodeCount = loweredNodeCount
    }
}
