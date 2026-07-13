import CircuiteFoundation
import Foundation
import XcircuitePackage

/// Converts between the retained Xcircuite compatibility reference and the
/// canonical Foundation artifact contract at the LogicEngine boundary.
public struct LogicFoundationArtifactBridge: Sendable {
    public init() {}

    public func legacyReference(
        from reference: ArtifactReference,
        runID: String,
        kind: XcircuiteFileKind? = nil,
        format: XcircuiteFileFormat? = nil
    ) throws -> XcircuiteFileReference {
        let path: String
        switch reference.locator.location.storage {
        case .workspaceRelative:
            path = reference.locator.location.value
        case .absoluteFileURL:
            guard let url = URL(string: reference.locator.location.value), url.isFileURL else {
                throw LogicFoundationBoundaryError.invalidArtifactLocation(
                    reference.locator.location.value,
                    reason: "the absolute file URL could not be decoded"
                )
            }
            path = url.path
        }
        guard let byteCount = Int64(exactly: reference.byteCount) else {
            throw LogicFoundationBoundaryError.byteCountOutOfRange(path)
        }
        return XcircuiteFileReference(
            artifactID: reference.id.rawValue,
            path: path,
            kind: kind ?? legacyKind(for: reference.locator.kind),
            format: format ?? legacyFormat(for: reference.locator.format),
            sha256: reference.digest.hexadecimalValue,
            byteCount: byteCount,
            producedByRunID: runID
        )
    }

    public func foundationReference(
        from reference: XcircuiteFileReference,
        defaultKind: ArtifactKind = .evidence,
        defaultFormat: ArtifactFormat = .json,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        guard let sha256 = reference.sha256, !sha256.isEmpty else {
            throw LogicFoundationBoundaryError.missingArtifactDigest(reference.path)
        }
        guard let byteCount = reference.byteCount, byteCount >= 0 else {
            throw LogicFoundationBoundaryError.byteCountOutOfRange(reference.path)
        }

        let location: ArtifactLocation
        do {
            if reference.path.hasPrefix("/") {
                location = try ArtifactLocation(fileURL: URL(filePath: reference.path))
            } else {
                location = try ArtifactLocation(workspaceRelativePath: reference.path)
            }
        } catch {
            throw LogicFoundationBoundaryError.invalidArtifactLocation(
                reference.path,
                reason: error.localizedDescription
            )
        }

        let digest: ContentDigest
        do {
            digest = try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256)
        } catch {
            throw LogicFoundationBoundaryError.invalidArtifactDigest(reference.path)
        }

        let artifactID: ArtifactID?
        if let rawArtifactID = reference.artifactID {
            do {
                artifactID = try ArtifactID(rawValue: rawArtifactID)
            } catch {
                throw LogicFoundationBoundaryError.invalidArtifactIdentity(rawArtifactID)
            }
        } else {
            artifactID = nil
        }

        return ArtifactReference(
            id: artifactID,
            locator: ArtifactLocator(
                location: location,
                kind: foundationKind(for: reference.kind, fallback: defaultKind),
                format: try foundationFormat(for: reference.format, fallback: defaultFormat)
            ),
            digest: digest,
            byteCount: UInt64(byteCount),
            producer: producer
        )
    }

    public func foundationDiagnostic(
        from diagnostic: XcircuiteEngineDiagnostic,
        namespace: String = "logic"
    ) throws -> DesignDiagnostic {
        let normalizedCode = token(diagnostic.code)
        let rawCode = normalizedCode.isEmpty ? "\(namespace).execution" : "\(namespace).\(normalizedCode)"
        let code: DiagnosticCode
        do {
            code = try DiagnosticCode(rawValue: rawCode)
        } catch {
            throw LogicFoundationBoundaryError.invalidDiagnosticCode(rawCode)
        }

        var subject: DesignObjectReference?
        if let entity = diagnostic.entity, !entity.isEmpty {
            do {
                subject = try DesignObjectReference(kind: .net, identifier: entity)
            } catch {
                subject = nil
            }
        } else {
            subject = nil
        }
        let actions = diagnostic.suggestedActions.map { action in
            SuggestedAction(
                code: "\(namespace).action.\(token(action))",
                summary: action
            )
        }
        return DesignDiagnostic(
            code: code,
            severity: foundationSeverity(for: diagnostic.severity),
            summary: diagnostic.message,
            detail: diagnostic.entity.map { "entity=\($0)" },
            subject: subject,
            suggestedActions: actions
        )
    }

    private func foundationKind(for kind: XcircuiteFileKind, fallback: ArtifactKind) -> ArtifactKind {
        switch kind {
        case .constraint:
            return .constraints
        case .netlist:
            return .netlist
        case .technology:
            return .technology
        case .waveform:
            return .waveform
        case .report, .designDiff, .release:
            return .report
        case .log:
            return .log
        default:
            return fallback
        }
    }

    private func foundationFormat(
        for format: XcircuiteFileFormat,
        fallback: ArtifactFormat
    ) throws -> ArtifactFormat {
        switch format {
        case .spice: return .spice
        case .systemVerilog: return .systemVerilog
        case .verilog: return .verilog
        case .oasis: return .oasis
        case .gdsii: return .gdsii
        case .lef: return .lef
        case .def: return .def
        case .spef: return .spef
        case .dspf: return .dspf
        case .liberty: return .liberty
        case .sdf: return .sdf
        case .vcd: return .vcd
        case .json: return .json
        default:
            let rawValue = format.rawValue.lowercased().replacingOccurrences(of: "_", with: "-")
            guard !rawValue.isEmpty, rawValue != "unknown" else { return fallback }
            do {
                return try ArtifactFormat(rawValue: rawValue)
            } catch {
                throw LogicFoundationBoundaryError.unsupportedArtifactFormat(format.rawValue)
            }
        }
    }

    private func legacyKind(for kind: ArtifactKind) -> XcircuiteFileKind {
        switch kind.rawValue.split(separator: ".").last.map(String.init) {
        case "constraints": return .constraint
        case "netlist": return .netlist
        case "technology": return .technology
        case "waveform": return .waveform
        case "report", "evidence": return .report
        case "log": return .log
        default: return .other
        }
    }

    private func legacyFormat(for format: ArtifactFormat) -> XcircuiteFileFormat {
        switch format.rawValue {
        case "spice": return .spice
        case "system-verilog": return .systemVerilog
        case "verilog": return .verilog
        case "oasis": return .oasis
        case "gdsii": return .gdsii
        case "lef": return .lef
        case "def": return .def
        case "spef": return .spef
        case "dspf": return .dspf
        case "liberty": return .liberty
        case "sdf": return .sdf
        case "vcd": return .vcd
        case "json": return .json
        default: return .unknown
        }
    }

    private func token(_ value: String) -> String {
        value.lowercased().map { character in
            if character.isLetter || character.isNumber || character == "." || character == "_" || character == "-" {
                return character
            }
            return "_"
        }.reduce(into: "") { result, character in
            result.append(character)
        }
    }

    private func foundationSeverity(
        for severity: XcircuiteEngineDiagnosticSeverity
    ) -> DiagnosticSeverity {
        switch severity {
        case .info: return .information
        case .warning: return .warning
        case .error: return .error
        }
    }
}
