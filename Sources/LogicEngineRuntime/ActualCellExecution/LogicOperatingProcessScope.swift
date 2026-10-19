import CircuiteFoundation
import LogicKernelCore
import STAEngine
import TimingCore

/// Declared source process premises; this value neither requests nor proves STA measurement.
public struct LogicOperatingProcessScope: Sendable, Hashable, Codable {
    public let libraries: [TimingLibraryReference]
    public let pdkManifest: TimingArtifactBinding
    public let processID: String
    public let pdkVersion: String
    public let cornerIDs: [String]
    public let characterizationBindings: [STACharacterizationBinding]

    public init(libraries: [TimingLibraryReference], pdkManifest: TimingArtifactBinding,
                processID: String, pdkVersion: String, cornerIDs: [String],
                characterizationBindings: [STACharacterizationBinding]) {
        self.libraries = libraries; self.pdkManifest = pdkManifest
        self.processID = processID; self.pdkVersion = pdkVersion
        self.cornerIDs = cornerIDs; self.characterizationBindings = characterizationBindings
    }

    internal func validate(library: ArtifactReference,
                          admit: (UInt64) throws(LogicKernelError) -> Void = { _ in }) throws(LogicKernelError) {
        try admit(UInt64(processID.utf8.count) + UInt64(pdkVersion.utf8.count) + 1)
        guard !processID.isEmpty, !pdkVersion.isEmpty, !cornerIDs.isEmpty,
              pdkManifest.descriptor.role == .input, pdkManifest.descriptor.format == .json,
              pdkManifest.digest.algorithm == .sha256,
              !libraries.isEmpty, characterizationBindings.count == cornerIDs.count else {
            throw .invalidInput("Incomplete or ambiguous functional operating process scope")
        }
        for index in cornerIDs.indices {
            let corner = cornerIDs[index]
            try admit(UInt64(corner.utf8.count) + 1)
            guard !corner.isEmpty else { throw .invalidInput("Empty functional operating corner") }
            for prior in 0..<index {
                try admit(UInt64(corner.utf8.count) + UInt64(cornerIDs[prior].utf8.count) + 1)
                guard cornerIDs[prior] != corner else { throw .invalidInput("Duplicate functional operating corner") }
            }
            var librariesForCorner = 0, conditionsForCorner = 0
            for reference in libraries {
                try admit(1)
                guard reference.artifact.reference == library, !reference.cornerIDs.isEmpty,
                      reference.artifact.descriptor.role == .input,
                      reference.artifact.descriptor.format == .liberty,
                      reference.artifact.digest.algorithm == .sha256 else {
                    throw .invalidInput("Foreign functional library reference")
                }
                for selected in reference.cornerIDs {
                    try admit(UInt64(corner.utf8.count) + UInt64(selected.utf8.count) + 1)
                    if selected == corner { librariesForCorner += 1 }
                }
            }
            for binding in characterizationBindings {
                try admit(UInt64(binding.cornerID.utf8.count) + UInt64(corner.utf8.count) + UInt64(binding.conditionName.utf8.count) + 1)
                guard !binding.conditionName.isEmpty, binding.requiredNumericProcess?.isFinite ?? true else {
                    throw .invalidInput("Invalid functional condition selection")
                }
                if binding.cornerID == corner { conditionsForCorner += 1 }
            }
            guard librariesForCorner == 1, conditionsForCorner == 1 else {
                throw .invalidInput("Missing or ambiguous functional corner selection")
            }
        }
        for reference in libraries {
            for corner in reference.cornerIDs {
                var found = false
                for expected in cornerIDs {
                    try admit(UInt64(corner.utf8.count) + UInt64(expected.utf8.count) + 1)
                    if corner == expected { found = true }
                }
                guard found else { throw .invalidInput("Foreign functional library corner") }
            }
        }
    }
}
