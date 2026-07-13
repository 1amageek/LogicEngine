import Foundation

public struct LogicCellLibraryDocument: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var libraryName: String
    public var cells: [LogicCell]

    public init(
        schemaVersion: Int = LogicCellLibraryDocument.currentSchemaVersion,
        libraryName: String,
        cells: [LogicCell]
    ) {
        self.schemaVersion = schemaVersion
        self.libraryName = libraryName
        self.cells = cells
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact("unsupported cell library schema version \(schemaVersion)")
        }
        guard !libraryName.isEmpty else {
            throw LogicExecutionError.invalidArtifact("cell library name is empty")
        }
        guard !cells.isEmpty else {
            throw LogicExecutionError.missingPrerequisite("cell library contains no cells")
        }
        let names = cells.map(\.name)
        guard Set(names).count == names.count else {
            throw LogicExecutionError.invalidArtifact("cell library contains duplicate cell names")
        }
        for cell in cells {
            guard cell.inputCount >= 0 else { throw LogicExecutionError.invalidArtifact("negative input count for \(cell.name)") }
            guard cell.area >= 0, cell.power >= 0 else { throw LogicExecutionError.invalidArtifact("negative cost for \(cell.name)") }
        }
    }

    public func qualifiedCell(for kind: LogicNodeKind, inputCount: Int) -> LogicCell? {
        cells
            .filter { $0.kind == kind && $0.inputCount == inputCount && $0.qualified }
            .sorted { lhs, rhs in
                if lhs.area != rhs.area { return lhs.area < rhs.area }
                if lhs.power != rhs.power { return lhs.power < rhs.power }
                return lhs.name < rhs.name
            }
            .first
    }
}
