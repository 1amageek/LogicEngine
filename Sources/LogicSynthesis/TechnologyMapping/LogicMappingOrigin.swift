import LogicIR

public struct LogicMappingOrigin: Sendable, Equatable {
    public let source: BitNodeIndex
    public let net: MappedNetIndex?
    internal init(source: BitNodeIndex, net: MappedNetIndex?) { self.source = source; self.net = net }
}
