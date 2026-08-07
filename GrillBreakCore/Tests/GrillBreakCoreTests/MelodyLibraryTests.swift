import Foundation
import Testing
@testable import GrillBreakCore

@Suite("MelodyLibrary")
struct MelodyLibraryTests {

    private func makeLibrary() throws -> (MelodyLibrary, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("melody-library-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = MelodyLibrary(rootDirectory: root)
        return (library, root)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    @Test("importing accepted MusicXML adds a melody that survives reload")
    func importPersistsAcrossReload() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let outcome = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures)
        guard case .imported(let melody, let warnings) = outcome else {
            Issue.record("expected imported, got \(outcome)")
            return
        }
        #expect(warnings.isEmpty)
        #expect(library.melodies().count == 1)
        #expect(library.melodies().first?.id == melody.id)

        let reloaded = MelodyLibrary(rootDirectory: root)
        #expect(reloaded.melodies().count == 1)
        #expect(reloaded.melodies().first?.id == melody.id)
        #expect(try reloaded.musicXML(for: melody.id) == MusicXMLFixtures.simpleFourMeasures)
    }

    @Test("rejected MusicXML is not added to the library")
    func rejectedMusicXMLNotAdded() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let outcome = library.importMusicXML(MusicXMLFixtures.withLyric)
        guard case .rejected(let reason) = outcome else {
            Issue.record("expected rejected, got \(outcome)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(library.melodies().isEmpty)
    }

    @Test("supports multiple melodies and deleting one")
    func supportsMultipleAndDelete() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        guard case .imported(let first, _) = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("first import failed")
            return
        }
        guard case .imported(let second, _) = library.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("second import failed")
            return
        }
        #expect(library.melodies().count == 2)

        try library.delete(id: first.id)
        let remaining = library.melodies()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == second.id)

        let reloaded = MelodyLibrary(rootDirectory: root)
        #expect(reloaded.melodies().count == 1)
        #expect(reloaded.melodies().first?.id == second.id)
    }

    @Test("manual selection persists and resolves the current melody")
    func manualSelectionPersists() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        guard case .imported(let first, _) = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("first import failed")
            return
        }
        guard case .imported(let second, _) = library.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("second import failed")
            return
        }

        try library.select(id: second.id)
        #expect(library.selectedMelodyID == second.id)
        #expect(library.currentMelody()?.id == second.id)
        #expect(first.id != second.id)

        let reloaded = MelodyLibrary(rootDirectory: root)
        #expect(reloaded.selectedMelodyID == second.id)
        #expect(reloaded.currentMelody()?.id == second.id)

        #expect(throws: MelodyLibraryError.self) {
            try library.select(id: UUID())
        }
        #expect(library.selectedMelodyID == second.id)
    }

    @Test("deleting the selected melody clears selection")
    func deletingSelectedClearsSelection() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        guard case .imported(let melody, _) = library.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("import failed")
            return
        }
        try library.select(id: melody.id)
        try library.delete(id: melody.id)
        #expect(library.selectedMelodyID == nil)
        #expect(library.currentMelody() == nil)
    }

    @Test("importing a file over 8 measures carries the gate warning")
    func importCarriesMeasureWarning() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let outcome = library.importMusicXML(MusicXMLFixtures.nineMeasures)
        guard case .imported(_, let warnings) = outcome else {
            Issue.record("expected imported, got \(outcome)")
            return
        }
        #expect(warnings.contains { $0.contains("8") })
    }

    @Test("MelodySelectionStrategy.manual resolves by id")
    func selectionStrategyManualResolves() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        guard case .imported(let melody, _) = library.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("import failed")
            return
        }

        let resolved = MelodySelection.resolve(
            melodies: library.melodies(),
            using: .manual(melodyID: melody.id)
        )
        #expect(resolved?.id == melody.id)

        let missing = MelodySelection.resolve(
            melodies: library.melodies(),
            using: .manual(melodyID: UUID())
        )
        #expect(missing == nil)
    }

    @Test("importing a .musicxml file URL succeeds")
    func importMusicXMLFileURL() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let fileURL = root.appendingPathComponent("incoming.musicxml")
        try MusicXMLFixtures.simpleFourMeasures.write(to: fileURL, atomically: true, encoding: .utf8)

        let outcome = library.importFile(at: fileURL)
        guard case .imported = outcome else {
            Issue.record("expected imported, got \(outcome)")
            return
        }
        #expect(library.melodies().count == 1)
    }
}

@Suite("MusicXMLFileLoader")
struct MusicXMLFileLoaderTests {

    @Test("loads plain .musicxml content")
    func loadsPlainMusicXML() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("sample.musicxml")
        try MusicXMLFixtures.twoMeasures.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try MusicXMLFileLoader().loadString(from: fileURL)
        #expect(loaded == MusicXMLFixtures.twoMeasures)
    }

    @Test("loads .mxl by extracting the score MusicXML")
    func loadsMXL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-pack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scoreName = "score.musicxml"
        let scoreURL = dir.appendingPathComponent(scoreName)
        try MusicXMLFixtures.twoMeasures.write(to: scoreURL, atomically: true, encoding: .utf8)

        let containerDir = dir.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container>
          <rootfiles>
            <rootfile full-path="\(scoreName)"/>
          </rootfiles>
        </container>
        """
        try container.write(
            to: containerDir.appendingPathComponent("container.xml"),
            atomically: true,
            encoding: .utf8
        )

        let mxlURL = dir.appendingPathComponent("sample.mxl")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", mxlURL.path, scoreName, "META-INF"]
        process.currentDirectoryURL = dir
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let loaded = try MusicXMLFileLoader().loadString(from: mxlURL)
        #expect(loaded.contains("score-partwise"))
        #expect(loaded.contains("<step>C</step>"))
    }
}
