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

    @Test("a save failure includes a short diagnostic detail")
    func saveFailureIncludesDiagnostic() throws {
        let (library, root) = try makeLibrary()
        let scores = root.appendingPathComponent("scores", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scores.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            cleanup(root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: scores.path)

        switch library.importMusicXML(MusicXMLFixtures.twoMeasures) {
        case .imported:
            Issue.record("expected rejection when the library cannot save")
        case .rejected(let reason):
            #expect(reason.contains("无法保存旋律文件。"))
            #expect(reason.contains("磁盘空间"))
            #expect(reason.contains("详情："))
            #expect(!reason.contains("exit"))
            let detail = reason.components(separatedBy: "详情：").last ?? ""
            #expect(!detail.isEmpty)
            #expect(detail.count <= 80)
        }
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
            #expect(reason.contains("该文件不是有效的 MXL 压缩包。"))
            #expect(reason.contains("重新导出 .musicxml / .mxl"))
            #expect(!reason.contains("详情"))
            #expect(!reason.contains("exit"))
        }
    }

    @Test("rejects mxl whose inner score filename contains non-ASCII characters")
    func rejectsMXLWithNonASCIIInnerName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-nonascii-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let innerName = "截屏2026-09-16 11.08.06.xml"
        let mxlURL = dir.appendingPathComponent("tests.mxl")
        try packedMXL(scoreName: innerName, xml: MusicXMLFixtures.twoMeasures).write(to: mxlURL)

        let library = MelodyLibrary(rootDirectory: dir.appendingPathComponent("lib"))
        switch library.importFile(at: mxlURL) {
        case .imported:
            Issue.record("expected rejection for non-ASCII inner name")
        case .rejected(let reason):
            #expect(reason.contains("压缩包内文件名为「\(innerName)」，含非英文字符，当前无法解压。"))
            #expect(reason.contains("把工程名改成英文后重新导出"))
            #expect(reason.contains(".musicxml"))
            #expect(!reason.contains("详情"))
        }
    }

    @Test("rejects mxl with multiple non-ASCII inner names using 等")
    func rejectsMXLWithMultipleNonASCIIInnerNames() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-nonascii-multi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mxlURL = dir.appendingPathComponent("tests.mxl")
        try packedMXL(
            scoreName: "甲.xml",
            xml: MusicXMLFixtures.twoMeasures,
            extraScoreNames: ["乙.xml"]
        ).write(to: mxlURL)

        let library = MelodyLibrary(rootDirectory: dir.appendingPathComponent("lib"))
        switch library.importFile(at: mxlURL) {
        case .imported:
            Issue.record("expected rejection for multiple non-ASCII names")
        case .rejected(let reason):
            #expect(reason.contains("压缩包内文件名为「甲.xml」等，含非英文字符，当前无法解压。"))
            #expect(!reason.contains("乙.xml"))
        }
    }

    @Test("truncates a long non-ASCII inner filename in the rejection")
    func truncatesLongNonASCIIInnerName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-nonascii-long-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let innerName = "截" + String(repeating: "a", count: 70) + ".xml"
        let mxlURL = dir.appendingPathComponent("tests.mxl")
        try packedMXL(scoreName: innerName, xml: MusicXMLFixtures.twoMeasures).write(to: mxlURL)

        let library = MelodyLibrary(rootDirectory: dir.appendingPathComponent("lib"))
        switch library.importFile(at: mxlURL) {
        case .imported:
            Issue.record("expected rejection for long non-ASCII name")
        case .rejected(let reason):
            let truncated = "截" + String(repeating: "a", count: 59) + "…"
            #expect(reason.contains("压缩包内文件名为「\(truncated)」，含非英文字符，当前无法解压。"))
            #expect(!reason.contains(".xml"))
        }
    }

    @Test("unreadable musicxml includes a short diagnostic detail")
    func unreadableMusicXMLIncludesDiagnostic() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-unreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("broken.musicxml")
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: fileURL)

        let library = MelodyLibrary(rootDirectory: dir.appendingPathComponent("lib"))
        switch library.importFile(at: fileURL) {
        case .imported:
            Issue.record("expected rejection for unreadable musicxml")
        case .rejected(let reason):
            #expect(reason.contains("无法读取该文件。"))
            #expect(reason.contains("导出 .musicxml"))
            #expect(reason.contains("详情："))
            #expect(!reason.contains("exit"))
            let detail = reason.components(separatedBy: "详情：").last ?? ""
            #expect(!detail.isEmpty)
            #expect(detail.count <= 80)
        }
    }

    @Test("unzip failure that is not a classified case includes a short diagnostic")
    func unzipOtherFailureIncludesDiagnostic() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-encrypted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scoreURL = dir.appendingPathComponent("score.musicxml")
        try MusicXMLFixtures.twoMeasures.write(to: scoreURL, atomically: true, encoding: .utf8)
        let containerDir = dir.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <container>
          <rootfiles>
            <rootfile full-path="score.musicxml"/>
          </rootfiles>
        </container>
        """.write(to: containerDir.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        let mxlURL = dir.appendingPathComponent("locked.mxl")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-P", "secret", "-q", mxlURL.path, "score.musicxml", "META-INF/container.xml"]
        zip.currentDirectoryURL = dir
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)

        let library = MelodyLibrary(rootDirectory: dir.appendingPathComponent("lib"))
        switch library.importFile(at: mxlURL) {
        case .imported:
            Issue.record("expected rejection for encrypted mxl")
        case .rejected(let reason):
            #expect(reason.contains("无法解压该 MXL 文件。"))
            #expect(reason.contains("导出为 .musicxml"))
            #expect(reason.contains("详情："))
            #expect(!reason.contains("exit"))
            let detail = reason.components(separatedBy: "详情：").last ?? ""
            #expect(detail.lowercased().contains("password"))
            #expect(detail.count <= 80)
        }
    }
}

private func packedMXL(scoreName: String, xml: String, extraScoreNames: [String] = []) throws -> Data {
    let scoreData = Data(xml.utf8)
    let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container>
          <rootfiles>
            <rootfile full-path="\(scoreName)"/>
          </rootfiles>
        </container>
        """
    var entries: [(String, Data)] = [(scoreName, scoreData)]
    for extra in extraScoreNames {
        entries.append((extra, scoreData))
    }
    entries.append(("META-INF/container.xml", Data(container.utf8)))
    return zipArchive(entries: entries)
}

private func zipArchive(entries: [(String, Data)]) -> Data {
    var locals = Data()
    var centrals = Data()
    var offset: UInt32 = 0
    for (name, fileData) in entries {
        let nameData = Data(name.utf8)
        let crc = zipCRC32(fileData)
        let size = UInt32(fileData.count)
        var local = Data()
        zipAppendU32(&local, 0x04034b50)
        zipAppendU16(&local, 20)
        zipAppendU16(&local, 0x0800)
        zipAppendU16(&local, 0)
        zipAppendU16(&local, 0)
        zipAppendU16(&local, 0)
        zipAppendU32(&local, crc)
        zipAppendU32(&local, size)
        zipAppendU32(&local, size)
        zipAppendU16(&local, UInt16(nameData.count))
        zipAppendU16(&local, 0)
        local.append(nameData)
        local.append(fileData)
        let localOffset = offset
        locals.append(local)
        offset += UInt32(local.count)

        var central = Data()
        zipAppendU32(&central, 0x02014b50)
        zipAppendU16(&central, 20)
        zipAppendU16(&central, 20)
        zipAppendU16(&central, 0x0800)
        zipAppendU16(&central, 0)
        zipAppendU16(&central, 0)
        zipAppendU16(&central, 0)
        zipAppendU32(&central, crc)
        zipAppendU32(&central, size)
        zipAppendU32(&central, size)
        zipAppendU16(&central, UInt16(nameData.count))
        zipAppendU16(&central, 0)
        zipAppendU16(&central, 0)
        zipAppendU16(&central, 0)
        zipAppendU16(&central, 0)
        zipAppendU32(&central, 0)
        zipAppendU32(&central, localOffset)
        central.append(nameData)
        centrals.append(central)
    }
    var eocd = Data()
    zipAppendU32(&eocd, 0x06054b50)
    zipAppendU16(&eocd, 0)
    zipAppendU16(&eocd, 0)
    zipAppendU16(&eocd, UInt16(entries.count))
    zipAppendU16(&eocd, UInt16(entries.count))
    zipAppendU32(&eocd, UInt32(centrals.count))
    zipAppendU32(&eocd, UInt32(locals.count))
    zipAppendU16(&eocd, 0)
    var archive = Data()
    archive.append(locals)
    archive.append(centrals)
    archive.append(eocd)
    return archive
}

private func zipCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFFFFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB88320
            } else {
                crc >>= 1
            }
        }
    }
    return crc ^ 0xFFFFFFFF
}

private func zipAppendU16(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
}

private func zipAppendU32(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
}
