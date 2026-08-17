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

    @Test("importing a file uses the filename stem as the melody title")
    func importFileUsesFilenameStemAsTitle() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let fileURL = root.appendingPathComponent("小星星.musicxml")
        try MusicXMLFixtures.simpleFourMeasures.write(to: fileURL, atomically: true, encoding: .utf8)

        let outcome = library.importFile(at: fileURL)
        guard case .imported(let melody, _) = outcome else {
            Issue.record("expected imported, got \(outcome)")
            return
        }
        #expect(melody.title == "小星星")
        #expect(library.melodies().first?.title == "小星星")
    }

    @Test("importing a .xml file uses the filename stem as the melody title")
    func importXMLFileUsesFilenameStemAsTitle() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let fileURL = root.appendingPathComponent("练习.xml")
        try MusicXMLFixtures.twoMeasures.write(to: fileURL, atomically: true, encoding: .utf8)

        let outcome = library.importFile(at: fileURL)
        guard case .imported(let melody, _) = outcome else {
            Issue.record("expected imported, got \(outcome)")
            return
        }
        #expect(melody.title == "练习")
    }

    @Test("importing a file with an empty filename stem is rejected")
    func importFileRejectsEmptyFilenameStem() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let fileURL = root.appendingPathComponent(".musicxml")
        try MusicXMLFixtures.simpleFourMeasures.write(to: fileURL, atomically: true, encoding: .utf8)

        let outcome = library.importFile(at: fileURL)
        guard case .rejected(let reason) = outcome else {
            Issue.record("expected rejected, got \(outcome)")
            return
        }
        #expect(reason == "文件名无效，请使用带主文件名的 .musicxml、.mxl 或 .xml。")
        #expect(library.melodies().isEmpty)
    }

    @Test("importing a duplicate filename stem appends the next free number")
    func importFileUniquifiesDuplicateFilenameStem() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        func writeFixture(_ xml: String, named name: String, under directory: URL) throws -> URL {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(name)
            try xml.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        let first = try writeFixture(
            MusicXMLFixtures.simpleFourMeasures,
            named: "小星星.musicxml",
            under: root.appendingPathComponent("a", isDirectory: true)
        )
        let second = try writeFixture(
            MusicXMLFixtures.twoMeasures,
            named: "小星星.musicxml",
            under: root.appendingPathComponent("b", isDirectory: true)
        )
        let third = try writeFixture(
            MusicXMLFixtures.twoMeasures,
            named: "小星星.musicxml",
            under: root.appendingPathComponent("c", isDirectory: true)
        )

        guard case .imported(let firstMelody, _) = library.importFile(at: first) else {
            Issue.record("first import failed")
            return
        }
        guard case .imported(let secondMelody, _) = library.importFile(at: second) else {
            Issue.record("second import failed")
            return
        }
        guard case .imported(let thirdMelody, _) = library.importFile(at: third) else {
            Issue.record("third import failed")
            return
        }
        #expect(firstMelody.title == "小星星")
        #expect(secondMelody.title == "小星星 2")
        #expect(thirdMelody.title == "小星星 3")
    }

    @Test("importing MusicXML without a file uses 未命名旋律")
    func importMusicXMLUsesDefaultTitle() throws {
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
        #expect(first.title == "未命名旋律")
        #expect(second.title == "未命名旋律 2")
    }

    @Test("a filename stem that already looks numbered is not parsed as a suffix")
    func importFileDoesNotParseExistingNumberSuffix() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        let firstDir = root.appendingPathComponent("a", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        let first = firstDir.appendingPathComponent("小星星 2.musicxml")
        try MusicXMLFixtures.simpleFourMeasures.write(to: first, atomically: true, encoding: .utf8)
        let secondDir = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        let second = secondDir.appendingPathComponent("小星星 2.musicxml")
        try MusicXMLFixtures.twoMeasures.write(to: second, atomically: true, encoding: .utf8)

        guard case .imported(let firstMelody, _) = library.importFile(at: first) else {
            Issue.record("first import failed")
            return
        }
        guard case .imported(let secondMelody, _) = library.importFile(at: second) else {
            Issue.record("second import failed")
            return
        }
        #expect(firstMelody.title == "小星星 2")
        #expect(secondMelody.title == "小星星 2 2")
    }

    @Test("renaming a melody persists across reload")
    func renamePersistsAcrossReload() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        guard case .imported(let melody, _) = library.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("import failed")
            return
        }
        try library.rename(id: melody.id, to: "  练习曲  ")
        #expect(library.melodies().first?.title == "练习曲")

        let reloaded = MelodyLibrary(rootDirectory: root)
        #expect(reloaded.melodies().first?.title == "练习曲")
        #expect(reloaded.melodies().first?.id == melody.id)
    }

    @Test("renaming to a blank title is rejected and keeps the original")
    func renameRejectsEmptyTitle() throws {
        let (library, root) = try makeLibrary()
        defer { cleanup(root) }

        guard case .imported(let melody, _) = library.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("import failed")
            return
        }
        #expect(throws: MelodyLibraryError.emptyTitle) {
            try library.rename(id: melody.id, to: "   ")
        }
        #expect(library.melodies().first?.title == "未命名旋律")
        #expect(MelodyLibraryError.emptyTitle.errorDescription == "名称不能为空。")
    }

    @Test("renaming to another melody's title is rejected")
    func renameRejectsDuplicateTitle() throws {
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
        try library.rename(id: first.id, to: "小星星")
        #expect(throws: MelodyLibraryError.duplicateTitle("小星星")) {
            try library.rename(id: second.id, to: "小星星")
        }
        #expect(library.melodies().first { $0.id == second.id }?.title == "未命名旋律 2")
        #expect(MelodyLibraryError.duplicateTitle("小星星").errorDescription == "已有同名旋律「小星星」。")
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

    @Test("rejects unsupported extensions with actionable reason")
    func rejectsUnsupportedExtension() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-badext-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let library = MelodyLibrary(rootDirectory: dir.appendingPathComponent("lib"))
        let bogus = dir.appendingPathComponent("notes.pdf")
        try! Data().write(to: bogus)

        switch library.importFile(at: bogus) {
        case .imported:
            Issue.record("expected rejection for .pdf")
        case .rejected(let reason):
            #expect(reason.contains("不支持的文件扩展名：pdf"))
            #expect(reason.contains("建议导入"))
            #expect(reason.contains(".musicxml"))
        }
    }

    @Test("maps corrupt mxl unzip failure to actionable Chinese copy")
    func mapsCorruptMXLToActionableCopy() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let library = MelodyLibrary(rootDirectory: dir.appendingPathComponent("lib"))
        let bogus = dir.appendingPathComponent("broken.mxl")
        try "not-a-zip".write(to: bogus, atomically: true, encoding: .utf8)

        switch library.importFile(at: bogus) {
        case .imported:
            Issue.record("expected rejection for corrupt mxl")
        case .rejected(let reason):
            #expect(reason.contains("无法解压该 MXL 文件"))
            #expect(reason.contains("导出为 .musicxml"))
            #expect(!reason.contains("exit"))
        }
    }
}
