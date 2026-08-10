import Foundation

/// An imported User Melody stored in the Melody Library.
public struct UserMelody: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let title: String
    public let measureCount: Int

    public init(id: UUID = UUID(), title: String, measureCount: Int) {
        self.id = id
        self.title = title
        self.measureCount = measureCount
    }
}

/// Outcome of attempting to add MusicXML to the Melody Library.
public enum MelodyImportOutcome: Equatable, Sendable {
    case imported(UserMelody, warnings: [String])
    case rejected(reason: String)
}

public enum MelodyLibraryError: Error, Equatable, Sendable {
    case melodyNotFound(UUID)
    case unsupportedFileExtension(String)
    case ioFailure(String)
}

/// Persists imported User Melodies under an injectable root directory and
/// tracks the manually selected "current" melody (Melody Selection v1).
public final class MelodyLibrary: @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let gate: MusicXMLImportGate
    private let fileLoader: MusicXMLFileLoader
    private let manifestURL: URL
    private let scoresDirectory: URL

    private var manifest: Manifest

    public init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        gate: MusicXMLImportGate = MusicXMLImportGate(),
        fileLoader: MusicXMLFileLoader = MusicXMLFileLoader()
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.gate = gate
        self.fileLoader = fileLoader
        self.manifestURL = rootDirectory.appendingPathComponent("manifest.json")
        self.scoresDirectory = rootDirectory.appendingPathComponent("scores", isDirectory: true)
        self.manifest = Manifest(melodies: [], selectedMelodyID: nil)

        try? fileManager.createDirectory(at: scoresDirectory, withIntermediateDirectories: true)
        if let loaded = try? loadManifest() {
            self.manifest = loaded
        } else {
            try? saveManifest()
        }
    }

    public func melodies() -> [UserMelody] {
        manifest.melodies
    }

    public var selectedMelodyID: UUID? {
        manifest.selectedMelodyID
    }

    /// Resolves the current melody using the stored manual selection.
    public func currentMelody() -> UserMelody? {
        guard let selectedMelodyID else { return nil }
        return MelodySelection.resolve(
            melodies: manifest.melodies,
            using: .manual(melodyID: selectedMelodyID)
        )
    }

    public func musicXML(for id: UUID) throws -> String {
        let url = scoreURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MelodyLibraryError.ioFailure(error.localizedDescription)
        }
    }

    @discardableResult
    public func importMusicXML(_ musicXML: String) -> MelodyImportOutcome {
        switch gate.evaluate(musicXML) {
        case .rejected(let reason):
            return .rejected(reason: reason)
        case .accepted(let draft):
            return store(draft: draft)
        }
    }

    @discardableResult
    public func importFile(at url: URL) -> MelodyImportOutcome {
        do {
            let musicXML = try fileLoader.loadString(from: url)
            return importMusicXML(musicXML)
        } catch let error as MelodyLibraryError {
            return .rejected(reason: errorDescription(error))
        } catch {
            return .rejected(reason: error.localizedDescription)
        }
    }

    public func select(id: UUID) throws {
        guard manifest.melodies.contains(where: { $0.id == id }) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        manifest.selectedMelodyID = id
        try saveManifest()
    }

    public func delete(id: UUID) throws {
        guard manifest.melodies.contains(where: { $0.id == id }) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        manifest.melodies.removeAll { $0.id == id }
        if manifest.selectedMelodyID == id {
            manifest.selectedMelodyID = nil
        }
        try saveManifest()
        let url = scoreURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Private

    private func store(draft: ImportedMelodyDraft) -> MelodyImportOutcome {
        let melody = UserMelody(title: draft.title, measureCount: draft.measureCount)
        do {
            try draft.musicXML.write(to: scoreURL(for: melody.id), atomically: true, encoding: .utf8)
            manifest.melodies.append(melody)
            if manifest.selectedMelodyID == nil {
                manifest.selectedMelodyID = melody.id
            }
            try saveManifest()
            return .imported(melody, warnings: draft.warnings)
        } catch {
            return .rejected(reason: error.localizedDescription)
        }
    }

    private func scoreURL(for id: UUID) -> URL {
        scoresDirectory.appendingPathComponent("\(id.uuidString).musicxml")
    }

    private func loadManifest() throws -> Manifest {
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func saveManifest() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func errorDescription(_ error: MelodyLibraryError) -> String {
        switch error {
        case .melodyNotFound(let id):
            return "找不到旋律：\(id.uuidString)"
        case .unsupportedFileExtension(let ext):
            return "不支持的文件扩展名：\(ext)"
        case .ioFailure(let message):
            return message
        }
    }

    private struct Manifest: Codable {
        var melodies: [UserMelody]
        var selectedMelodyID: UUID?
    }
}

/// Melody Selection strategies. v1 is manual pick; later strategies (e.g. random)
/// can be added without changing library storage.
public enum MelodySelectionStrategy: Sendable, Equatable {
    case manual(melodyID: UUID)
}

public enum MelodySelection {
    public static func resolve(
        melodies: [UserMelody],
        using strategy: MelodySelectionStrategy
    ) -> UserMelody? {
        switch strategy {
        case .manual(let melodyID):
            return melodies.first { $0.id == melodyID }
        }
    }
}
