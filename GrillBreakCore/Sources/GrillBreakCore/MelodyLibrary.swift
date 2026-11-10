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
    /// The melody is still in the library, but its score file is not on this Mac yet.
    case scoreNotLocal

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
        case .scoreNotLocal:
            return "这份旋律还不能读。若刚从另一台 Mac 同步，请稍候，不要再次导入。"
        }
    }
}

/// Whether this Mac is using the owner's shared Melody Library or its private one.
public enum MelodyLibraryResidence: Equatable, Sendable {
    case shared
    case privateLibrary
}

/// Persists imported User Melodies and the manual current melody.
///
/// Each Mac writes only its own device log. `reload()` merges every log in the
/// active directory, so two Macs sharing one directory converge without either
/// overwriting the other's file. The manual current melody stays in
/// `localStateDirectory` and is never written into the shared directory.
/// When `sharedContainerIsReachable` is true and the shared directory is a
/// different folder, a private library there is folded in once and then retired.
public final class MelodyLibrary: @unchecked Sendable {
    private let sharedDirectory: URL
    private let privateDirectory: URL
    private let localStateDirectory: URL
    private let sharedContainerIsReachable: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let gate: MusicXMLImportGate
    private let fileLoader: MusicXMLFileLoader
    private let deviceID: UUID
    private let lock = NSLock()

    private var residence: MelodyLibraryResidence = .privateLibrary
    private var manualSelection: UUID?
    private var ourRecords: [UUID: DeviceMelodyRecord] = [:]
    private var displayMelodies: [UserMelody] = []
    private var tombstonedIDs: Set<UUID> = []

    /// Private library at `rootDirectory`, including its manual selection.
    /// Used when this Mac cannot reach the shared library.
    public convenience init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        gate: MusicXMLImportGate = MusicXMLImportGate(),
        fileLoader: MusicXMLFileLoader = MusicXMLFileLoader()
    ) {
        self.init(
            sharedDirectory: rootDirectory,
            privateDirectory: rootDirectory,
            localStateDirectory: rootDirectory,
            sharedContainerIsReachable: { false },
            now: Date.init,
            fileManager: fileManager,
            gate: gate,
            fileLoader: fileLoader
        )
    }

    /// `sharedDirectory` is the owner's shared library when the container is
    /// reachable. `privateDirectory` is this Mac's private library otherwise.
    /// `localStateDirectory` holds this Mac's device id and manual selection.
    public init(
        sharedDirectory: URL,
        privateDirectory: URL,
        localStateDirectory: URL,
        sharedContainerIsReachable: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default,
        gate: MusicXMLImportGate = MusicXMLImportGate(),
        fileLoader: MusicXMLFileLoader = MusicXMLFileLoader()
    ) {
        self.sharedDirectory = sharedDirectory
        self.privateDirectory = privateDirectory
        self.localStateDirectory = localStateDirectory
        self.sharedContainerIsReachable = sharedContainerIsReachable
        self.now = now
        self.fileManager = fileManager
        self.gate = gate
        self.fileLoader = fileLoader
        if !fileManager.fileExists(atPath: localStateDirectory.path) {
            try? fileManager.createDirectory(at: localStateDirectory, withIntermediateDirectories: true)
        }
        self.deviceID = Self.loadOrCreateDeviceID(in: localStateDirectory, fileManager: fileManager)
        self.manualSelection = Self.readSelection(in: localStateDirectory, fileManager: fileManager)
        activate()
    }

    public func melodies() -> [UserMelody] {
        lock.lock()
        defer { lock.unlock() }
        return displayMelodies
    }

    public var currentResidence: MelodyLibraryResidence {
        lock.lock()
        defer { lock.unlock() }
        return residence
    }

    public var residenceSummary: String {
        switch currentResidence {
        case .shared:
            return "曲库在 iCloud 云盘，同一 Apple ID 的 Mac 会保持一致。"
        case .privateLibrary:
            return "曲库只在这台 Mac 上。iCloud 云盘不可用，其他 Mac 看不到这里的旋律。"
        }
    }

    public var selectedMelodyID: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return manualSelection
    }

    public func currentMelody() -> UserMelody? {
        lock.lock()
        defer { lock.unlock() }
        guard let manualSelection else { return nil }
        return displayMelodies.first { $0.id == manualSelection }
    }

    public func musicXML(for id: UUID) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard displayMelodies.contains(where: { $0.id == id }) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        let url = scoreURL(for: id, in: activeDirectory)
        guard fileManager.fileExists(atPath: url.path) else {
            requestDownloadIfUbiquitous(url)
            throw MelodyLibraryError.scoreNotLocal
        }
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            requestDownloadIfUbiquitous(url)
            throw MelodyLibraryError.scoreNotLocal
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MelodyLibraryError.ioFailure(error.localizedDescription)
        }
    }

    /// Re-reads the active library and folds a private library in when the
    /// shared container is reachable. Returns whether membership, titles,
    /// selection, residence, or score-file presence changed.
    @discardableResult
    public func reload() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let before = snapshot()
        activate()
        return snapshot() != before
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
        lock.lock()
        defer { lock.unlock() }
        guard displayMelodies.contains(where: { $0.id == id }) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        manualSelection = id
        try saveSelection()
    }

    public func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard displayMelodies.contains(where: { $0.id == id }) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        var record = ourRecords[id] ?? synthesizedRecord(id: id)
        record.deletedAt = now()
        ourRecords[id] = record
        if manualSelection == id {
            manualSelection = nil
            try saveSelection()
        }
        try saveOurLog()
        let url = scoreURL(for: id, in: activeDirectory)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        rebuildMerged()
    }

    public func rename(id: UUID, to rawTitle: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let current = displayMelodies.first(where: { $0.id == id }) else {
            throw MelodyLibraryError.melodyNotFound(id)
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw MelodyLibraryError.emptyTitle
        }
        if displayMelodies.contains(where: { $0.id != id && $0.title == title }) {
            throw MelodyLibraryError.duplicateTitle(title)
        }
        if current.title == title {
            return
        }
        var record = ourRecords[id] ?? synthesizedRecord(id: id)
        record.title = title
        record.titleChangedAt = now()
        record.deletedAt = nil
        ourRecords[id] = record
        try saveOurLog()
        rebuildMerged()
    }

    // MARK: - Activation

    private var activeDirectory: URL {
        residence == .shared ? sharedDirectory : privateDirectory
    }

    private func activate() {
        if sharedContainerIsReachable(), !sameDirectory(sharedDirectory, privateDirectory) {
            residence = .shared
            ensureLibraryDirectories(sharedDirectory)
            loadOurRecords(from: sharedDirectory)
            foldPrivateLibraryIntoShared()
            adoptLegacyManifest(in: sharedDirectory)
        } else if sharedContainerIsReachable() {
            residence = .shared
            ensureLibraryDirectories(sharedDirectory)
            loadOurRecords(from: sharedDirectory)
            adoptLegacyManifest(in: sharedDirectory)
        } else {
            residence = .privateLibrary
            ensureLibraryDirectories(privateDirectory)
            loadOurRecords(from: privateDirectory)
            adoptLegacyManifest(in: privateDirectory)
        }
        rebuildMerged()
        clearSelectionIfTombstoned()
    }

    private func foldPrivateLibraryIntoShared() {
        guard !sameDirectory(privateDirectory, sharedDirectory) else { return }
        guard privateLogsAreReadable() else { return }
        let contribution = privateContribution()
        guard contribution.hasCatalog else { return }

        if manualSelection == nil, let selection = contribution.selection {
            manualSelection = selection
            try? saveSelection()
        }

        let buried = tombstones(in: sharedDirectory)
        let before = ourRecords
        var copiesSucceeded = true
        for record in contribution.records {
            if buried.contains(record.id), record.deletedAt == nil {
                continue
            }
            if !mergePrivateRecord(record) {
                copiesSucceeded = false
            }
        }
        var saved = true
        if ourRecords != before {
            do {
                try saveOurLog()
            } catch {
                saved = false
            }
        }
        if copiesSucceeded && saved {
            retirePrivateCatalog()
        }
    }

    /// Returns false when a score that exists only in the private library could not be copied.
    private func mergePrivateRecord(_ record: DeviceMelodyRecord) -> Bool {
        guard var existing = ourRecords[record.id] else {
            ourRecords[record.id] = record
            if record.deletedAt == nil {
                return copyPrivateScore(id: record.id)
            }
            removeSharedScore(id: record.id)
            return true
        }
        if record.deletedAt != nil || existing.deletedAt != nil {
            existing.deletedAt = [record.deletedAt, existing.deletedAt].compactMap { $0 }.min()
            existing.importedAt = min(existing.importedAt, record.importedAt)
            ourRecords[record.id] = existing
            removeSharedScore(id: record.id)
            return true
        }
        existing.importedAt = min(existing.importedAt, record.importedAt)
        if record.titleChangedAt >= existing.titleChangedAt {
            existing.title = record.title
            existing.titleChangedAt = record.titleChangedAt
        }
        ourRecords[record.id] = existing
        return copyPrivateScore(id: record.id)
    }

    private func adoptLegacyManifest(in directory: URL) {
        let url = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard let manifest = readLegacyManifest(at: url) else { return }
        if manualSelection == nil {
            manualSelection = manifest.selectedMelodyID
            do {
                try saveSelection()
            } catch {
                manualSelection = nil
                return
            }
        }
        let buried = tombstones(in: directory)
        let base = Date(timeIntervalSince1970: 0)
        var changed = false
        for (index, melody) in manifest.melodies.enumerated() {
            if ourRecords[melody.id] != nil || buried.contains(melody.id) {
                continue
            }
            let when = base.addingTimeInterval(TimeInterval(index))
            ourRecords[melody.id] = DeviceMelodyRecord(
                id: melody.id,
                title: melody.title,
                measureCount: melody.measureCount,
                importedAt: when,
                titleChangedAt: when,
                deletedAt: nil
            )
            changed = true
        }
        if changed {
            do {
                try saveOurLog()
            } catch {
                return
            }
        }
        try? fileManager.removeItem(at: url)
    }

    private func retirePrivateCatalog() {
        let root = privateDirectory
        try? fileManager.removeItem(at: root.appendingPathComponent("manifest.json"))
        try? fileManager.removeItem(at: root.appendingPathComponent("devices", isDirectory: true))
        try? fileManager.removeItem(at: root.appendingPathComponent("scores", isDirectory: true))
        if !sameDirectory(root, localStateDirectory) {
            try? fileManager.removeItem(at: root.appendingPathComponent("selection.json"))
            try? fileManager.removeItem(at: root.appendingPathComponent("device-id"))
        }
    }

    private func clearSelectionIfTombstoned() {
        guard let manualSelection, tombstonedIDs.contains(manualSelection) else { return }
        self.manualSelection = nil
        try? saveSelection()
    }

    private func loadOurRecords(from directory: URL) {
        let url = deviceLogURL(in: directory)
        guard let data = try? Data(contentsOf: url),
              let file = try? Self.makeDecoder().decode(DeviceLogFile.self, from: data) else {
            ourRecords = [:]
            return
        }
        ourRecords = Dictionary(uniqueKeysWithValues: file.records.map { ($0.id, $0) })
    }

    private func rebuildMerged() {
        var logs = readAllDeviceLogs(in: activeDirectory)
        logs.removeAll { $0.deviceID == deviceID }
        logs.append((deviceID, ourRecords.values.sorted(by: Self.recordOrder)))
        let merged = Self.merge(logs)
        tombstonedIDs = Set(merged.filter(\.isDeleted).map(\.id))
        displayMelodies = Self.displayMelodies(from: merged.filter { !$0.isDeleted })
    }

    // MARK: - Import

    private static let emptyFilenameStemMessage = "文件名无效，请使用带主文件名的 .musicxml、.mxl 或 .xml。"
    private static let supportedTitleExtensions: Set<String> = ["musicxml", "mxl", "xml"]

    private func importAccepted(_ musicXML: String, title: String) -> MelodyImportOutcome {
        lock.lock()
        defer { lock.unlock() }
        switch gate.evaluate(musicXML) {
        case .rejected(let reason):
            return .rejected(reason: reason)
        case .accepted(let draft):
            return store(draft: draft, title: uniquifiedTitle(title))
        }
    }

    private func uniquifiedTitle(_ base: String) -> String {
        Self.uniquified(base, taken: Set(displayMelodies.map(\.title)))
    }

    private func store(draft: ImportedMelodyDraft, title: String) -> MelodyImportOutcome {
        let melodyID = UUID()
        let when = now()
        let record = DeviceMelodyRecord(
            id: melodyID,
            title: title,
            measureCount: draft.measureCount,
            importedAt: when,
            titleChangedAt: when,
            deletedAt: nil
        )
        let score = scoreURL(for: melodyID, in: activeDirectory)
        do {
            ensureLibraryDirectories(activeDirectory)
            try draft.musicXML.write(to: score, atomically: true, encoding: .utf8)
            var updated = ourRecords
            updated[melodyID] = record
            try saveOurLog(updated)
            ourRecords = updated
        } catch {
            try? fileManager.removeItem(at: score)
            return .rejected(reason: MusicXMLFileLoader.fallbackMessage(
                """
                无法保存旋律文件。
                请检查磁盘空间后重试。
                """,
                diagnostic: error.localizedDescription
            ))
        }
        if manualSelection == nil {
            manualSelection = melodyID
            try? saveSelection()
        }
        rebuildMerged()
        let shown = displayMelodies.first { $0.id == melodyID }
            ?? UserMelody(id: melodyID, title: title, measureCount: draft.measureCount)
        return .imported(shown, warnings: draft.warnings)
    }

    // MARK: - Files

    private func scoreURL(for id: UUID, in directory: URL) -> URL {
        directory
            .appendingPathComponent("scores", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).musicxml")
    }

    private func deviceLogURL(in directory: URL) -> URL {
        directory
            .appendingPathComponent("devices", isDirectory: true)
            .appendingPathComponent("\(deviceID.uuidString).json")
    }

    private func ensureLibraryDirectories(_ directory: URL) {
        for url in [
            directory,
            directory.appendingPathComponent("scores", isDirectory: true),
            directory.appendingPathComponent("devices", isDirectory: true)
        ] where !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func saveOurLog() throws {
        try saveOurLog(ourRecords)
    }

    private func saveOurLog(_ records: [UUID: DeviceMelodyRecord]) throws {
        ensureLibraryDirectories(activeDirectory)
        let payload = DeviceLogFile(records: records.values.sorted(by: Self.recordOrder))
        let data = try Self.makeEncoder().encode(payload)
        try data.write(to: deviceLogURL(in: activeDirectory), options: .atomic)
    }

    private func saveSelection() throws {
        if !fileManager.fileExists(atPath: localStateDirectory.path) {
            try fileManager.createDirectory(at: localStateDirectory, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(SelectionFile(selectedMelodyID: manualSelection))
        try data.write(to: localStateDirectory.appendingPathComponent("selection.json"), options: .atomic)
    }

    private func requestDownloadIfUbiquitous(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        let placeholder = URL(fileURLWithPath: url.path + ".icloud")
        guard values?.isUbiquitousItem == true || fileManager.fileExists(atPath: placeholder.path) else {
            return
        }
        try? fileManager.startDownloadingUbiquitousItem(at: url)
    }

    private func copyPrivateScore(id: UUID) -> Bool {
        let source = scoreURL(for: id, in: privateDirectory)
        let destination = scoreURL(for: id, in: sharedDirectory)
        if !fileManager.fileExists(atPath: source.path) {
            return true
        }
        if fileManager.fileExists(atPath: destination.path) {
            return true
        }
        ensureLibraryDirectories(sharedDirectory)
        do {
            try fileManager.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    private func removeSharedScore(id: UUID) {
        let url = scoreURL(for: id, in: sharedDirectory)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func synthesizedRecord(id: UUID) -> DeviceMelodyRecord {
        let shown = displayMelodies.first { $0.id == id }
        return DeviceMelodyRecord(
            id: id,
            title: shown?.title ?? "",
            measureCount: shown?.measureCount ?? 0,
            importedAt: now(),
            titleChangedAt: now(),
            deletedAt: nil
        )
    }

    private func snapshot() -> Snapshot {
        var bytes: [UUID: Int] = [:]
        for melody in displayMelodies {
            bytes[melody.id] = scoreByteCount(melody.id)
        }
        return Snapshot(
            residence: residence,
            selection: manualSelection,
            melodies: displayMelodies,
            scoreBytes: bytes
        )
    }

    private func scoreByteCount(_ id: UUID) -> Int {
        let url = scoreURL(for: id, in: activeDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return -1 }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey])
        if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            return -1
        }
        return values?.fileSize ?? 0
    }

    // MARK: - Private catalog

    private struct PrivateContribution {
        var records: [DeviceMelodyRecord]
        var selection: UUID?
        var hasCatalog: Bool
    }

    private func privateContribution() -> PrivateContribution {
        var records: [UUID: DeviceMelodyRecord] = [:]
        for (_, logRecords) in readAllDeviceLogs(in: privateDirectory) {
            for record in logRecords {
                records[record.id] = record
            }
        }
        var selection = Self.readSelection(in: privateDirectory, fileManager: fileManager)
        var hasCatalog = !records.isEmpty || selection != nil
        if let manifest = readLegacyManifest(at: privateDirectory.appendingPathComponent("manifest.json")) {
            hasCatalog = true
            if selection == nil {
                selection = manifest.selectedMelodyID
            }
            let base = Date(timeIntervalSince1970: 0)
            for (index, melody) in manifest.melodies.enumerated() where records[melody.id] == nil {
                let when = base.addingTimeInterval(TimeInterval(index))
                records[melody.id] = DeviceMelodyRecord(
                    id: melody.id,
                    title: melody.title,
                    measureCount: melody.measureCount,
                    importedAt: when,
                    titleChangedAt: when,
                    deletedAt: nil
                )
            }
        }
        let scores = privateDirectory.appendingPathComponent("scores", isDirectory: true)
        if fileManager.fileExists(atPath: scores.path) {
            hasCatalog = true
        }
        if fileManager.fileExists(atPath: privateDirectory.appendingPathComponent("devices").path) {
            hasCatalog = true
        }
        return PrivateContribution(records: Array(records.values), selection: selection, hasCatalog: hasCatalog)
    }

    private func privateLogsAreReadable() -> Bool {
        let directory = privateDirectory.appendingPathComponent("devices", isDirectory: true)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return true }
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  (try? Self.makeDecoder().decode(DeviceLogFile.self, from: data)) != nil else {
                return false
            }
        }
        return true
    }

    private func tombstones(in directory: URL) -> Set<UUID> {
        var ids = Set<UUID>()
        for (_, records) in readAllDeviceLogs(in: directory) {
            for record in records where record.deletedAt != nil {
                ids.insert(record.id)
            }
        }
        return ids
    }

    private func readAllDeviceLogs(in directory: URL) -> [(deviceID: UUID, records: [DeviceMelodyRecord])] {
        let directory = directory.appendingPathComponent("devices", isDirectory: true)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var logs: [(deviceID: UUID, records: [DeviceMelodyRecord])] = []
        for url in urls where url.pathExtension == "json" {
            guard let deviceID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url),
                  let file = try? Self.makeDecoder().decode(DeviceLogFile.self, from: data) else {
                continue
            }
            logs.append((deviceID, file.records))
        }
        return logs
    }

    private func readLegacyManifest(at url: URL) -> LegacyManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LegacyManifest.self, from: data)
    }

    // MARK: - Names and paths

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

    private func sameDirectory(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func uniquified(_ base: String, taken: Set<String>) -> String {
        if !taken.contains(base) {
            return base
        }
        var n = 2
        while taken.contains("\(base) \(n)") {
            n += 1
        }
        return "\(base) \(n)"
    }

    private static func recordOrder(_ lhs: DeviceMelodyRecord, _ rhs: DeviceMelodyRecord) -> Bool {
        if lhs.importedAt != rhs.importedAt {
            return lhs.importedAt < rhs.importedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func loadOrCreateDeviceID(in directory: URL, fileManager: FileManager) -> UUID {
        let url = directory.appendingPathComponent("device-id")
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return id
        }
        let id = UUID()
        try? Data(id.uuidString.utf8).write(to: url, options: .atomic)
        return id
    }

    private static func readSelection(in directory: URL, fileManager: FileManager) -> UUID? {
        let url = directory.appendingPathComponent("selection.json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SelectionFile.self, from: data) else {
            return nil
        }
        return file.selectedMelodyID
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func merge(
        _ logs: [(deviceID: UUID, records: [DeviceMelodyRecord])]
    ) -> [MergedMelody] {
        struct Seen {
            var deviceID: UUID
            var record: DeviceMelodyRecord
        }
        var grouped: [UUID: [Seen]] = [:]
        for (deviceID, records) in logs {
            for record in records {
                grouped[record.id, default: []].append(Seen(deviceID: deviceID, record: record))
            }
        }
        return grouped.map { id, seen in
            let earliest = seen.min { lhs, rhs in
                if lhs.record.importedAt != rhs.record.importedAt {
                    return lhs.record.importedAt < rhs.record.importedAt
                }
                return lhs.deviceID.uuidString < rhs.deviceID.uuidString
            }
            let titleSource = seen.max { lhs, rhs in
                if lhs.record.titleChangedAt != rhs.record.titleChangedAt {
                    return lhs.record.titleChangedAt < rhs.record.titleChangedAt
                }
                return lhs.deviceID.uuidString < rhs.deviceID.uuidString
            }
            return MergedMelody(
                id: id,
                storedTitle: titleSource?.record.title ?? "",
                measureCount: earliest?.record.measureCount ?? 0,
                importedAt: earliest?.record.importedAt ?? .distantPast,
                titleChangedAt: titleSource?.record.titleChangedAt ?? .distantPast,
                isDeleted: seen.contains { $0.record.deletedAt != nil }
            )
        }
    }

    private static func displayMelodies(from alive: [MergedMelody]) -> [UserMelody] {
        let claimOrder = alive.sorted { lhs, rhs in
            if lhs.titleChangedAt != rhs.titleChangedAt {
                return lhs.titleChangedAt < rhs.titleChangedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var taken = Set<String>()
        var titles: [UUID: String] = [:]
        for melody in claimOrder {
            let title = uniquified(melody.storedTitle, taken: taken)
            titles[melody.id] = title
            taken.insert(title)
        }
        let displayOrder = alive.sorted { lhs, rhs in
            if lhs.importedAt != rhs.importedAt {
                return lhs.importedAt < rhs.importedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return displayOrder.map { melody in
            UserMelody(
                id: melody.id,
                title: titles[melody.id] ?? melody.storedTitle,
                measureCount: melody.measureCount
            )
        }
    }

    private struct Snapshot: Equatable {
        var residence: MelodyLibraryResidence
        var selection: UUID?
        var melodies: [UserMelody]
        var scoreBytes: [UUID: Int]
    }

    private struct DeviceLogFile: Codable {
        var records: [DeviceMelodyRecord]
    }

    private struct DeviceMelodyRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var measureCount: Int
        var importedAt: Date
        var titleChangedAt: Date
        var deletedAt: Date?
    }

    private struct MergedMelody {
        var id: UUID
        var storedTitle: String
        var measureCount: Int
        var importedAt: Date
        var titleChangedAt: Date
        var isDeleted: Bool
    }

    private struct SelectionFile: Codable {
        var selectedMelodyID: UUID?
    }

    private struct LegacyManifest: Codable {
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
        melodyID: UUID?
    ) -> UserMelody? {
        guard let melodyID else { return nil }
        return melodies.first { $0.id == melodyID }
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

    /// Melody fixed for the rest underway, including while a delay or a
    /// postpone-after-delay is waiting to show it again. `nil` means no rest
    /// is held. `melodyID == nil` means this rest has no melody.
    private var heldRest: HeldMelody?

    private struct HeldMelody: Equatable {
        var melodyID: UUID?
    }

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
            melody = MelodySelection.resolve(melodies: melodies, melodyID: melodyID)
        case .randomNoRepeat:
            melody = randomMelody(from: melodies)
        }
        heldRest = HeldMelody(melodyID: melody?.id)
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
