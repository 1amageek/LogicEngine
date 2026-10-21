import Foundation
import PDKCore
import PDKDiscovery

/// Audits only the Runtime schemas' custom Codable boundaries, not arbitrary JSON.
internal enum LogicReloadCodingAudit {
    private enum Key: String, CodingKey {
        case request, originalBitDesign, mappedIdentities, netlist, proof, timingResult, operatingConditions
        case sources, artifact, library, operatingConditionPolicies, operatingProcessScope, constraints, timing
        case policies, records, libraries, pdkManifest, reference, availability, id, artifactID, descriptor
        case role, kind, format, rootID, relativePath, resource, serviceID, namespaceID, resourceID
        case limits, kernelMaximums
        case producer, identifier, version, build
    }

    static func receipt(_ decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        try producer(c.superDecoder(forKey: .producer))
        for key in [Key.request, .originalBitDesign, .mappedIdentities, .netlist, .proof] {
            try binding(c.superDecoder(forKey: key))
        }
        if c.contains(.timingResult), try !c.decodeNil(forKey: .timingResult) {
            try binding(c.superDecoder(forKey: .timingResult))
        }
        let conditions = try c.superDecoder(forKey: .operatingConditions).container(keyedBy: Key.self)
        try references(conditions.superDecoder(forKey: .policies), field: .library)
        try references(conditions.superDecoder(forKey: .records), field: .library)
    }

    private static func producer(_ decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        try token(c.superDecoder(forKey: .identifier))
        try token(c.superDecoder(forKey: .version))
        if c.contains(.build), try !c.decodeNil(forKey: .build) {
            try token(c.superDecoder(forKey: .build))
        }
    }

    static func request(_ decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var sources = try c.superDecoder(forKey: .sources).unkeyedContainer()
        while !sources.isAtEnd {
            let source = try sources.superDecoder().container(keyedBy: Key.self)
            try binding(source.superDecoder(forKey: .artifact))
        }
        try binding(c.superDecoder(forKey: .library))
        try references(c.superDecoder(forKey: .operatingConditionPolicies), field: .library)
        if c.contains(.operatingProcessScope), try !c.decodeNil(forKey: .operatingProcessScope) {
            try scope(c.superDecoder(forKey: .operatingProcessScope))
        }
        let constraints = try c.superDecoder(forKey: .constraints).container(keyedBy: Key.self)
        if constraints.contains(.timing), try !constraints.decodeNil(forKey: .timing) {
            let timing = try constraints.superDecoder(forKey: .timing)
            try scope(timing)
            try binding(timing.container(keyedBy: Key.self).superDecoder(forKey: .constraints))
        }
        let limits = try c.superDecoder(forKey: .limits).container(keyedBy: Key.self)
        let maximums = try limits.superDecoder(forKey: .kernelMaximums)
        let array = try maximums.unkeyedContainer()
        guard let count = array.count, count.isMultiple(of: 2) else {
            throw PDKBoundedDecodeError.unsupportedValue("Invalid kernel-limit dictionary representation")
        }
        // UInt8-key Dictionary uses an alternating array, not a JSON object.
        // Offer encoded pairs, including duplicates: the standard decoder may
        // reserve from its unkeyed count before it replaces repeated UInt8 keys.
        let entries = UInt64(count / 2)
        let expanded = entries.multipliedReportingOverflow(by: 4)
        guard !expanded.overflow else { throw PDKAdmissionResourceError.arithmeticOverflow(.liveOwnedBytes) }
        let required = expanded.partialValue / 3 + 1
        var buckets: UInt64 = 1
        while buckets < required {
            try work(1, decoder: maximums)
            let next = buckets.multipliedReportingOverflow(by: 2)
            guard !next.overflow else { throw PDKAdmissionResourceError.arithmeticOverflow(.liveOwnedBytes) }
            buckets = next.partialValue
        }
        let stride = UInt64(MemoryLayout<UInt8>.stride + MemoryLayout<UInt64>.stride)
        let payload = buckets.multipliedReportingOverflow(by: stride)
        let occupancy = (buckets / UInt64(UInt.bitWidth) + 1).multipliedReportingOverflow(by: UInt64(MemoryLayout<UInt>.stride))
        let subtotal = payload.partialValue.addingReportingOverflow(occupancy.partialValue)
        let total = subtotal.partialValue.multipliedReportingOverflow(by: 2)
        guard !payload.overflow, !occupancy.overflow, !subtotal.overflow, !total.overflow else {
            throw PDKAdmissionResourceError.arithmeticOverflow(.liveOwnedBytes)
        }
        // Old/new buckets coexist while decoding; allocator buckets are excluded.
        try reserve(total.partialValue, kind: .liveOwnedBytes, decoder: maximums)
    }

    private static func scope(_ decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        try binding(c.superDecoder(forKey: .pdkManifest))
        var libraries = try c.superDecoder(forKey: .libraries).unkeyedContainer()
        while !libraries.isAtEnd {
            let library = try libraries.superDecoder().container(keyedBy: Key.self)
            try binding(library.superDecoder(forKey: .artifact))
        }
    }

    private static func references(_ decoder: any Decoder, field: Key) throws {
        var array = try decoder.unkeyedContainer()
        while !array.isAtEnd {
            let item = try array.superDecoder().container(keyedBy: Key.self)
            try reference(item.superDecoder(forKey: field))
        }
    }

    private static func binding(_ decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        try reference(c.superDecoder(forKey: .reference))
        let availability = try c.superDecoder(forKey: .availability)
        let a = try availability.container(keyedBy: Key.self)
        try artifactID(a.superDecoder(forKey: .artifactID))
        try token(a.superDecoder(forKey: .kind))
        if a.contains(.rootID) { try token(a.superDecoder(forKey: .rootID)) }
        if a.contains(.relativePath) {
            var segments = try a.superDecoder(forKey: .relativePath).unkeyedContainer()
            while !segments.isAtEnd { try token(segments.superDecoder()) }
        }
        if a.contains(.resource) {
            let resource = try a.superDecoder(forKey: .resource).container(keyedBy: Key.self)
            for key in [Key.serviceID, .namespaceID, .resourceID] { try token(resource.superDecoder(forKey: key)) }
        }
    }

    private static func reference(_ decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        try artifactID(c.superDecoder(forKey: .id))
        let descriptor = try c.superDecoder(forKey: .descriptor).container(keyedBy: Key.self)
        for key in [Key.role, .kind, .format] { try token(descriptor.superDecoder(forKey: key)) }
    }

    private static func artifactID(_ decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // Actual Runtime integrity verification already requires SHA-256. The header
        // is CF's fixed canonical domain/version/algorithm/digest-length representation.
        let header = "43697263756974654172746966616374436f6e74656e7400000100067368613235360020"
        try work(UInt64(value.utf8.count), decoder: decoder)
        guard value.utf8.count == 152, value.utf8.starts(with: header.utf8) else {
            throw PDKBoundedDecodeError.unsupportedValue("Controlled reload requires canonical SHA-256 artifact IDs")
        }
        let domain = UInt64("CircuiteArtifactContent".utf8.count)
        let algorithm: UInt64 = 6, digest: UInt64 = 32
        // Enumerate CF's raw hex/decoded/domain/length/algorithm/digest/hex buffers.
        let arrays: UInt64 = 152 + 76 + domain + domain + algorithm + algorithm
            + digest + 16 + 2 * digest + 3 * 2 + 8
        try reserve(arrays + 2 * digest, kind: .temporaryBytes, decoder: decoder)
        // CF retains the ASCII algorithm token and normalized hexadecimal digest.
        try reserve(algorithm + 2 * digest, kind: .liveOwnedBytes, decoder: decoder)
        try work(arrays + algorithm + 4 * digest, decoder: decoder)
    }

    private static func token(_ decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // Token/path validation checks first, last and scalar content without growing payload.
        let count = UInt64(value.utf8.count)
        let total = count.multipliedReportingOverflow(by: 3)
        guard !total.overflow else { throw PDKAdmissionResourceError.arithmeticOverflow(.parserWork) }
        try work(total.partialValue, decoder: decoder)
    }

    private static func accounting(_ decoder: any Decoder) throws -> any PDKAdmissionResourceAccounting {
        guard let accounting = decoder.userInfo[PDKAdmissionDecodingContext.accountingKey]
                as? any PDKAdmissionResourceAccounting else {
            throw PDKAdmissionResourceError.unsupportedBudgetCapability("Missing audited decoder accounting")
        }
        return accounting
    }
    private static func reserve(_ bytes: UInt64, kind: PDKAdmissionResourceDimension,
                                decoder: any Decoder) throws {
        guard bytes > 0 else { return }
        _ = try accounting(decoder).reserve(PDKAdmissionCost(dimension: kind, amount: bytes))
    }
    private static func work(_ amount: UInt64, decoder: any Decoder) throws {
        guard amount > 0 else { return }
        try accounting(decoder).charge(PDKAdmissionCost(dimension: .parserWork, amount: amount))
    }
}
