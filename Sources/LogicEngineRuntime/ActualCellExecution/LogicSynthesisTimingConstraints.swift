import STAEngine
import TimingCore

public struct LogicSynthesisTimingConstraints: Sendable, Hashable, Codable {
    public var operatingProcessScope: LogicOperatingProcessScope {
        .init(libraries: libraries, pdkManifest: pdkManifest, processID: processID,
              pdkVersion: pdkVersion, cornerIDs: cornerIDs, characterizationBindings: characterizationBindings)
    }
    public let libraries: [TimingLibraryReference]
    public let constraints: TimingArtifactBinding
    public let pdkManifest: TimingArtifactBinding
    public let processID: String
    public let pdkVersion: String
    public let cornerIDs: [String]
    public let modeIDs: [String]
    public let characterizationBindings: [STACharacterizationBinding]
    public let minimumSetupSlack: Double?
    public let minimumHoldSlack: Double?
    public let maximumPaths: Int
    public init(libraries: [TimingLibraryReference], constraints: TimingArtifactBinding,
                pdkManifest: TimingArtifactBinding, processID: String, pdkVersion: String,
                cornerIDs: [String], modeIDs: [String], characterizationBindings: [STACharacterizationBinding],
                minimumSetupSlack: Double?, minimumHoldSlack: Double?, maximumPaths: Int) {
        self.libraries = libraries; self.constraints = constraints; self.pdkManifest = pdkManifest
        self.processID = processID; self.pdkVersion = pdkVersion; self.cornerIDs = cornerIDs
        self.modeIDs = modeIDs; self.characterizationBindings = characterizationBindings
        self.minimumSetupSlack = minimumSetupSlack; self.minimumHoldSlack = minimumHoldSlack; self.maximumPaths = maximumPaths
    }
}
