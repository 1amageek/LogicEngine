import LogicIR
import TimingCore

/// One mapped-connectivity projection shared by ordinary and controlled reload.
internal enum LogicReloadTimingProjection {
    static func build(_ mapped: borrowing MappedGateDesign, top: String,
        resources: (any LibertySourceResourceAccounting)? = nil) throws
        -> (value: TimingDesign, retention: LibertySourceStorageReservation?) {
        try mapped.withTables { nets, instances, pins, ports, bits, _ in
            var byteCount: UInt64 = 0
            func add(_ value: UInt64) throws {
                let next = byteCount.addingReportingOverflow(value)
                guard !next.overflow else { throw LibertySourceError.arithmeticOverflow }
                byteCount = next.partialValue
            }
            func array<T>(_ type: T.Type, _ count: Int) throws {
                let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(MemoryLayout<T>.stride))
                guard !bytes.overflow else { throw LibertySourceError.arithmeticOverflow }
                try add(bytes.partialValue)
            }
            func integerWidth(_ value: Int) throws -> UInt64 {
                var current = value; var count: UInt64 = 1
                while current >= 10 { try resources?.chargeWork(1); current /= 10; count += 1 }
                return count
            }
            func table(_ count: Int, key: UInt64, value: UInt64) throws {
                let expanded = UInt64(count).multipliedReportingOverflow(by: 4)
                guard !expanded.overflow else { throw LibertySourceError.arithmeticOverflow }
                let required = expanded.partialValue / 3 + 1
                var buckets: UInt64 = 1
                while buckets < required {
                    try resources?.chargeWork(1)
                    let next = buckets.multipliedReportingOverflow(by: 2)
                    guard !next.overflow else { throw LibertySourceError.arithmeticOverflow }
                    buckets = next.partialValue
                }
                let fields = key.addingReportingOverflow(value)
                let payload = buckets.multipliedReportingOverflow(by: fields.partialValue)
                let occupancy = (buckets / UInt64(UInt.bitWidth) + 1)
                    .multipliedReportingOverflow(by: UInt64(MemoryLayout<UInt>.stride))
                let total = payload.partialValue.addingReportingOverflow(occupancy.partialValue)
                let coexist = total.partialValue.multipliedReportingOverflow(by: 2)
                guard !fields.overflow, !payload.overflow, !occupancy.overflow,
                      !total.overflow, !coexist.overflow else { throw LibertySourceError.arithmeticOverflow }
                try add(coexist.partialValue)
            }
            var portCount = 0
            if resources != nil {
                try array(String.self, nets.count)
                try array(TimingDesign.Net.self, nets.count)
                try array(TimingDesign.Instance.self, instances.count)
                try table(nets.count, key: UInt64(MemoryLayout<Int>.stride), value: 0)
                for index in nets.indices {
                    try resources?.check(); try resources?.chargeWork(1)
                    try add(1 + integerWidth(index))
                }
                for index in ports.indices {
                    let sum = portCount.addingReportingOverflow(ports[index].bits.count)
                    guard !sum.overflow else { throw LibertySourceError.arithmeticOverflow }
                    portCount = sum.partialValue
                    for bit in 0..<ports[index].bits.count {
                        try resources?.check(); try resources?.chargeWork(1)
                        let width = try 2 + integerWidth(index) + integerWidth(bit)
                        // The first-name assignment and port construction coexist.
                        try add(width); try add(width)
                    }
                }
                try array(TimingDesign.Port.self, portCount)
                for index in instances.indices {
                    try resources?.check(); try resources?.chargeWork(1)
                    try add(1 + integerWidth(index))
                    let cell = try mapped.library.cell(at: instances[index].cell)
                    try table(cell.pinCount, key: UInt64(MemoryLayout<String>.stride), value: UInt64(MemoryLayout<String>.stride))
                }
            }
            let retention: LibertySourceStorageReservation?
            if let resources {
                try resources.check()
                retention = try resources.reserveStorage(kind: .temporaryBytes, byteCount: byteCount)
                try resources.check()
            } else { retention = nil }
            var names: [String] = []
            names.reserveCapacity(nets.count)
            for index in nets.indices {
                try resources?.check(); try resources?.chargeWork(1)
                names.append("n\(index)")
            }
            var assigned = Set<Int>()
            if resources != nil { assigned.reserveCapacity(nets.count) }
            for port in ports.indices {
                for bit in 0..<ports[port].bits.count {
                    try resources?.check(); try resources?.chargeWork(1)
                    let net = bits[ports[port].bits.lowerBound + bit].rawValue
                    if assigned.insert(net).inserted { names[net] = "p\(port)_\(bit)" }
                }
            }
            var timingPorts: [TimingDesign.Port] = []
            if resources != nil { timingPorts.reserveCapacity(portCount) }
            for port in ports.indices {
                for bit in 0..<ports[port].bits.count {
                    try resources?.check(); try resources?.chargeWork(1)
                    let net = bits[ports[port].bits.lowerBound + bit].rawValue
                    let name = "p\(port)_\(bit)"
                    timingPorts.append(.init(name: name, direction: ports[port].direction == .input ? .input : .output,
                        net: names[net] == name ? nil : names[net]))
                }
            }
            var timingNets: [TimingDesign.Net] = []
            if resources != nil { timingNets.reserveCapacity(nets.count) }
            for net in nets.indices {
                try resources?.check(); try resources?.chargeWork(1)
                let constant: TimingDesign.Constant?
                if case .constant(let value) = nets[net].driver { constant = value ? .one : .zero }
                else { constant = nil }
                timingNets.append(.init(name: names[net], constant: constant))
            }
            var timingInstances: [TimingDesign.Instance] = []
            if resources != nil { timingInstances.reserveCapacity(instances.count) }
            for instance in instances.indices {
                try resources?.check(); try resources?.chargeWork(1)
                let cell = try mapped.library.cell(at: instances[instance].cell)
                var connections: [String: String] = [:]
                if resources != nil { connections.reserveCapacity(cell.pinCount) }
                for pin in 0..<cell.pinCount {
                    let name = try cell.pin(at: .init(pin)).name
                    try resources?.check(); try resources?.chargeWork(UInt64(name.utf8.count) + 1)
                    connections[name] = names[pins[instances[instance].pins.lowerBound + pin].rawValue]
                }
                timingInstances.append(.init(name: "i\(instance)", cell: cell.name, connections: connections))
            }
            return (TimingDesign(topDesignName: top, ports: timingPorts,
                instances: timingInstances, nets: timingNets), retention)
        }
    }
}
