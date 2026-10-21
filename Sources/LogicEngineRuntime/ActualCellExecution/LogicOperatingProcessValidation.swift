import CircuiteFoundation
import Foundation
import LogicKernelCore
import PDKCore
import PDKDiscovery
import TimingCore

/// Joins public manifest and original Liberty facts; it performs no timing analysis.
internal enum LogicOperatingProcessValidation {
    static func validate(_ request: LogicSynthesisRequest, source: borrowing OwnedLibertySource,
                         io: inout LogicRuntimeIO, context: inout LogicKernelContext) throws {
        guard let scope = request.operatingProcessScope else { return }
        try context.checkpoint()
        try scope.validate(library: request.library.reference) { amount throws(LogicKernelError) in
            try context.charge(.workUnits, amount: amount)
        }
        let data = try io.read(NativeLogicSynthesisEngine.logicBinding(scope.pdkManifest), context: &context)
        let controlledManifest: PDKControlledManifest?
        let manifest: PDKManifest
        if let controlled = io.controlled {
            let result = try LogicReloadDocumentDecoding.manifest(data: data, limits: io.limits,
                context: &context, resources: controlled.resources)
            controlledManifest = result
            manifest = result.manifest
        } else {
            // Preserve the legacy host codec and its original accounting profile.
            _ = try context.reserveStorage(byteCount: UInt64(data.count))
            try context.charge(.workUnits, amount: UInt64(data.count))
            manifest = try PDKManifestCodec.decode(data: data)
            controlledManifest = nil
        }
        defer { withExtendedLifetime(controlledManifest) {} }
        let limit = min(request.limits.maximumTableEntries, io.limits.maximumTableEntries)
        var records = 0
        func count(_ amount: Int) throws {
            try context.charge(.workUnits)
            let next = records.addingReportingOverflow(amount)
            guard amount >= 0, !next.overflow, next.partialValue <= limit else {
                throw LogicKernelError.invalidInput("Functional process manifest exceeds the table ceiling")
            }
            records = next.partialValue
        }
        try count(manifest.assets.count); try count(manifest.layers.count); try count(manifest.devices.count)
        try count(manifest.corners.count); try count(manifest.crossViewMappings.count)
        try count(manifest.metadata.count)
        for asset in manifest.assets { try count(asset.cornerIDs.count); try count(asset.metadata.count) }
        for layer in manifest.layers { try count(layer.aliases.count) }
        for device in manifest.devices {
            try count(device.terminals.count); try count(device.parameterNames.count); try count(device.aliases.count)
        }
        for corner in manifest.corners { try count(corner.assetIDs.count); try count(corner.viewMappings.count) }
        for mapping in manifest.crossViewMappings {
            try count(mapping.cornerIDs.count); try count(mapping.layerIDs.count)
            try count(mapping.deviceIDs.count); try count(mapping.logicalNames.count); try count(mapping.physicalNames.count)
        }
        let bytes = UInt64(records).multipliedReportingOverflow(by: UInt64(MemoryLayout<PDKValidationFinding>.stride))
        guard !bytes.overflow else { throw LogicKernelError.invalidInput("Functional process workspace overflows") }
        _ = try context.reserveStorage(byteCount: bytes.partialValue)
        try context.charge(.nodes, amount: UInt64(records))
        try context.charge(.workUnits, amount: UInt64(records))
        let valid = controlledManifest?.validation.isValid ?? manifest.validate().isValid
        guard valid,
              try same(manifest.processID, scope.processID, context: &context),
              try same(manifest.version, scope.pdkVersion, context: &context) else {
            throw LogicKernelError.invalidInput("Functional process scope differs from the captured manifest")
        }
        for cornerID in scope.cornerIDs {
            var corner: PDKCornerDefinition?
            for candidate in manifest.corners {
                if try same(candidate.cornerID, cornerID, context: &context) {
                    guard corner == nil else { throw LogicKernelError.invalidInput("Ambiguous functional process corner") }
                    corner = candidate
                }
            }
            guard let corner, !corner.pvt.process.name.isEmpty,
                  corner.pvt.voltage.isFinite, corner.pvt.voltage > 0,
                  corner.pvt.temperatureCelsius.isFinite,
                  let assetID = corner.viewMappings["liberty"] else {
                throw LogicKernelError.invalidInput("Functional process corner lacks explicit PVT or Liberty mapping")
            }
            var included = false
            for id in corner.assetIDs { if try same(id, assetID, context: &context) { included = true } }
            var asset: PDKAssetReference?
            for candidate in manifest.assets {
                if try same(candidate.assetID, assetID, context: &context) {
                    guard asset == nil else { throw LogicKernelError.invalidInput("Ambiguous functional library asset") }
                    asset = candidate
                }
            }
            guard included, let asset, asset.format == .liberty, let digest = asset.sha256,
                  try sameHexadecimal(digest, request.library.digest.hexadecimalValue, context: &context),
                  asset.byteCount.flatMap(UInt64.init(exactly:)) == request.library.byteCount else {
                throw LogicKernelError.invalidInput("Functional library bytes differ from the manifest corner asset")
            }
            var assetCorner = false, crossView = false
            for id in asset.cornerIDs { if try same(id, cornerID, context: &context) { assetCorner = true } }
            for mapping in manifest.crossViewMappings {
                try context.charge(.workUnits)
                guard mapping.view == .liberty, try same(mapping.assetID, assetID, context: &context) else { continue }
                for id in mapping.cornerIDs { if try same(id, cornerID, context: &context) { crossView = true } }
            }
            guard assetCorner, crossView else { throw LogicKernelError.invalidInput("Functional corner lacks a manifest Liberty association") }
            var bindingIndex: Int?
            for index in scope.characterizationBindings.indices {
                if try same(scope.characterizationBindings[index].cornerID, cornerID, context: &context) {
                    guard bindingIndex == nil else { throw LogicKernelError.invalidInput("Duplicate functional condition selection") }
                    bindingIndex = index
                }
            }
            guard let bindingIndex else { throw LogicKernelError.invalidInput("Missing functional condition selection") }
            let binding = scope.characterizationBindings[bindingIndex]
            var conditionIndex: Int?
            for index in source.operatingConditions.indices {
                if try same(source.operatingConditions[index].name, binding.conditionName, context: &context) {
                    guard conditionIndex == nil else { throw LogicKernelError.invalidInput("Ambiguous source operating condition") }
                    conditionIndex = index
                }
            }
            guard let conditionIndex else { throw LogicKernelError.invalidInput("Missing explicit source operating condition") }
            let condition = source.operatingConditions[conditionIndex]
            try context.charge(.workUnits, amount: 3)
            guard condition.voltage == corner.pvt.voltage,
                  condition.temperature == corner.pvt.temperatureCelsius,
                  binding.requiredNumericProcess == nil || condition.process == binding.requiredNumericProcess else {
                throw LogicKernelError.invalidInput("Source voltage, Celsius or numeric process differs from the functional corner")
            }
        }
        try context.checkpoint()
    }

    private static func same(_ lhs: String, _ rhs: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        let size = UInt64(lhs.utf8.count).addingReportingOverflow(UInt64(rhs.utf8.count))
        guard !size.overflow else { throw .invalidInput("Process identity comparison overflows") }
        try context.charge(.workUnits, amount: size.partialValue)
        return lhs == rhs
    }

    private static func sameHexadecimal(_ lhs: String, _ rhs: String, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        var left = lhs.utf8.makeIterator(), right = rhs.utf8.makeIterator()
        while true {
            try context.charge(.workUnits)
            let a = left.next(), b = right.next()
            guard let a, let b else { return a == nil && b == nil }
            let normalized = a >= 65 && a <= 70 ? a + 32 : a
            if normalized != b { return false }
        }
    }
}
