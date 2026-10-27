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

public enum MelodyLibraryError: Error, Equatable, Sendable, LocalizedError {
    case melodyNotFound(UUID)
    case unsupportedFileExtension(String)
    case ioFailure(String)
    case emptyTitle
    case duplicateTitle(String)

    public var errorDescription: String? {
        switch self {
        case .melodyNotFound(let id):
            return "找不到旋律：\(id.uuidString)"
        case .unsupportedFileExtension(let ext):
            return """
                不支持的文件扩展名：\(ext)。
                建议导入 MuseScore 或 Audiveris 导出的 .musicxml / .mxl 文件。
                """
        case .ioFailure(let message):
            return message
        case .emptyTitle:
            return "名称不能为空。"
        case .duplicateTitle(let title):
            return "已有同名旋律「\(title)」。"
        }
    }
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
        importAccepted(musicXML, title: "未命名旋律")
    }

    @discardableResult
    public func importFile(at url: URL) -> MelodyImportOutcome {
        if isSupportedMusicXMLURL(url), fileTitle(from: url) == nil {
            return .rejected(reason: Self.emptyFilenameStemMessage)
        }
        do {
            let musicXML = try fileLoader.loadString(from: url)
            guard let title = fileTitle(from: url) else {
                return .rejected(reason: Self.emptyFilenameStemMessage)
            }
            return importAccepted(musicXML, title: title)
        } catch let error as MelodyLibraryError {
            return .rejected(reason: error.errorDescription ?? "")
        } catch {
            return .rejected(reason: MusicXMLFileLoader.fallbackMessage(
                MusicXMLFileLoader.unreadableFileMessage,
                diagnostic: error.localizedDescription
            ))
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

    public func rename(id: UUID, to rawTitle: String) throws {
        guard let index = manifest.melodies.firstIndex(where: { $0.id == id }) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw MelodyLibraryError.emptyTitle
        }
        if manifest.melodies.contains(where: { $0.id != id && $0.title == title }) {
            throw MelodyLibraryError.duplicateTitle(title)
        }
        let existing = manifest.melodies[index]
        if existing.title == title {
            return
        }
        manifest.melodies[index] = UserMelody(
            id: existing.id,
            title: title,
            measureCount: existing.measureCount
        )
        try saveManifest()
    }

    // MARK: - Private

    private static let emptyFilenameStemMessage = "文件名无效，请使用带主文件名的 .musicxml、.mxl 或 .xml。"
    private static let supportedTitleExtensions: Set<String> = ["musicxml", "mxl", "xml"]

    private func isBareSupportedFilename(_ url: URL) -> Bool {
        switch url.lastPathComponent.lowercased() {
        case ".musicxml", ".mxl", ".xml":
            return true
        default:
            return false
        }
    }

    private func isSupportedMusicXMLURL(_ url: URL) -> Bool {
        isBareSupportedFilename(url)
            || Self.supportedTitleExtensions.contains(url.pathExtension.lowercased())
    }

    private func fileTitle(from url: URL) -> String? {
        if isBareSupportedFilename(url) {
            return nil
        }
        let stem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? nil : stem
    }

    private func importAccepted(_ musicXML: String, title: String) -> MelodyImportOutcome {
        switch gate.evaluate(musicXML) {
        case .rejected(let reason):
            return .rejected(reason: reason)
        case .accepted(let draft):
            return store(draft: draft, title: uniquifiedTitle(title))
        }
    }

    private func uniquifiedTitle(_ base: String) -> String {
        let taken = Set(manifest.melodies.map(\.title))
        if !taken.contains(base) {
            return base
        }
        var n = 2
        while taken.contains("\(base) \(n)") {
            n += 1
        }
        return "\(base) \(n)"
    }

    private func store(draft: ImportedMelodyDraft, title: String) -> MelodyImportOutcome {
        let melody = UserMelody(title: title, measureCount: draft.measureCount)
        do {
            try draft.musicXML.write(to: scoreURL(for: melody.id), atomically: true, encoding: .utf8)
            manifest.melodies.append(melody)
            if manifest.selectedMelodyID == nil {
                manifest.selectedMelodyID = melody.id
            }
            try saveManifest()
            return .imported(melody, warnings: draft.warnings)
        } catch {
            return .rejected(reason: MusicXMLFileLoader.fallbackMessage(
                """
                无法保存旋律文件。
                请检查磁盘空间后重试。
                """,
                diagnostic: error.localizedDescription
            ))
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

    private struct Manifest: Codable {
        var melodies: [UserMelody]
        var selectedMelodyID: UUID?
    }
}

/// Melody Selection strategies. Manual pick keeps the library's current melody.
/// Random draws a User Melody for one rest and does not write that choice back
/// onto the manual selection.
public enum MelodySelectionStrategy: Sendable, Equatable {
    case manual(melodyID: UUID?)
    /// Equal chance among the library, excluding the melody shown on the
    /// previous Staff Melody rest when that still leaves at least one melody.
    case randomNoRepeat
}

public enum MelodySelection {
    /// Resolves a manual Melody Selection. Random draws go through
    /// `MelodySelectionState`, which also remembers the last shown melody.
    public static func resolve(
        melodies: [UserMelody],
        using strategy: MelodySelectionStrategy
    ) -> UserMelody? {
        switch strategy {
        case .manual(let melodyID):
            guard let melodyID else { return nil }
            return melodies.first { $0.id == melodyID }
        case .randomNoRepeat:
            return nil
        }
    }
}

/// Melody fixed for the rest that is underway, including while a delay or a
/// postpone-after-delay is waiting to show it again.
public struct MelodyHeldRest: Equatable, Sendable {
    /// `nil` when this rest has no melody: empty library, or no manual pick.
    public var melodyID: UUID?

    public init(melodyID: UUID?) {
        self.melodyID = melodyID
    }
}

/// In-process Melody Selection for Staff Melody rests.
///
/// `lastShownMelodyID` is the melody actually chosen for the most recent
/// Staff Melody rest that had one. An empty rest does not clear it. The held
/// rest survives dismissing the overlay for a delay; it is not process state
/// and is not restored after relaunch — callers persist only `lastShownMelodyID`.
public final class MelodySelectionState: @unchecked Sendable {
    public private(set) var lastShownMelodyID: UUID?
    public private(set) var heldRest: MelodyHeldRest?

    private let randomIndex: (Int) -> Int

    /// - Parameter randomIndex: Given a pool size, returns the index to pick.
    ///   Must be in `0..<poolSize`. Tests pass a fixed index; production uses
    ///   `Int.random(in:)`.
    public init(
        lastShownMelodyID: UUID? = nil,
        randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }
    ) {
        self.lastShownMelodyID = lastShownMelodyID
        self.randomIndex = randomIndex
    }

    /// Chooses the User Melody for a Staff Melody rest that is about to appear.
    ///
    /// A continuing rest keeps `heldRest` when that melody is still in the
    /// library, including an explicit empty choice. If the held melody was
    /// removed, draws again with random-no-repeat against the current library.
    /// A new rest draws with `strategy` and replaces the hold. A draw that
    /// finds no melody leaves `lastShownMelodyID` unchanged.
    @discardableResult
    public func beginPresentation(
        melodies: [UserMelody],
        using strategy: MelodySelectionStrategy,
        continuingSameRest: Bool
    ) -> UserMelody? {
        if continuingSameRest, let heldRest {
            if let melodyID = heldRest.melodyID,
               let melody = melodies.first(where: { $0.id == melodyID }) {
                return melody
            }
            if heldRest.melodyID == nil {
                return nil
            }
            return draw(melodies: melodies, using: .randomNoRepeat)
        }
        return draw(melodies: melodies, using: strategy)
    }

    private func draw(
        melodies: [UserMelody],
        using strategy: MelodySelectionStrategy
    ) -> UserMelody? {
        let melody: UserMelody?
        switch strategy {
        case .manual(let melodyID):
            melody = MelodySelection.resolve(melodies: melodies, using: .manual(melodyID: melodyID))
        case .randomNoRepeat:
            melody = randomMelody(from: melodies)
        }
        heldRest = MelodyHeldRest(melodyID: melody?.id)
        if let melody {
            lastShownMelodyID = melody.id
        }
        return melody
    }

    private func randomMelody(from melodies: [UserMelody]) -> UserMelody? {
        guard !melodies.isEmpty else { return nil }
        let excludingLast = melodies.filter { $0.id != lastShownMelodyID }
        let pool = excludingLast.isEmpty ? melodies : excludingLast
        return pool[randomIndex(pool.count)]
    }
}
