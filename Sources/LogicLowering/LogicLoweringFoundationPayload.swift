import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Foundation-native lowering metrics and execution-design projection.
public struct LogicLoweringFoundationPayload: Sendable, Hashable, Codable {
    public let sourceDesignDigest: ContentDigest?
    public let executionDesign: LogicFoundationDesignReference?
    public let loweredSignalCount: Int
    public let loweredNodeCount: Int

    public init(
        sourceDesignDigest: ContentDigest? = nil,
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
