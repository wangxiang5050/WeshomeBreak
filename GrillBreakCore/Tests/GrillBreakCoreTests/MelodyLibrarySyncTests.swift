import Foundation
import Testing
@testable import GrillBreakCore

@Suite("Melody Library sync")
struct MelodyLibrarySyncTests {
    private final class Clock: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
        func now() -> Date { date }
        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    }

    private final class Reachability: @unchecked Sendable {
        var value: Bool
        init(_ value: Bool) { self.value = value }
        func callAsFunction() -> Bool { value }
    }

    private struct Pair {
        let root: URL
        let libraryA: MelodyLibrary
        let libraryB: MelodyLibrary
        let clockA: Clock
        let clockB: Clock
        let reachability: Reachability
    }

    private func makePair(reachable: Bool = true) throws -> Pair {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("melody-sync-\(UUID().uuidString)", isDirectory: true)
        let shared = root.appendingPathComponent("shared", isDirectory: true)
        let privateA = root.appendingPathComponent("private-a", isDirectory: true)
        let privateB = root.appendingPathComponent("private-b", isDirectory: true)
        let localA = root.appendingPathComponent("local-a", isDirectory: true)
        let localB = root.appendingPathComponent("local-b", isDirectory: true)
        let clockA = Clock(Date(timeIntervalSince1970: 1_700_000_000))
        let clockB = Clock(Date(timeIntervalSince1970: 1_700_000_100))
        let reachability = Reachability(reachable)
        let libraryA = MelodyLibrary(
            sharedDirectory: shared,
            privateDirectory: privateA,
            localStateDirectory: localA,
            sharedContainerIsReachable: { reachability.value },
            now: { clockA.now() }
        )
        let libraryB = MelodyLibrary(
            sharedDirectory: shared,
            privateDirectory: privateB,
            localStateDirectory: localB,
            sharedContainerIsReachable: { reachability.value },
            now: { clockB.now() }
        )
        return Pair(
            root: root,
            libraryA: libraryA,
            libraryB: libraryB,
            clockA: clockA,
            clockB: clockB,
            reachability: reachability
        )
    }

    @Test("melodies imported on two Macs both appear, in import order")
    func unionKeepsBothImports() throws {
        let pair = try makePair()
        defer { try? FileManager.default.removeItem(at: pair.root) }

        guard case .imported(let first, _) = pair.libraryA.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("first import failed")
            return
        }
        guard case .imported(let second, _) = pair.libraryB.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("second import failed")
            return
        }

        pair.libraryA.reload()
        pair.libraryB.reload()

        #expect(pair.libraryA.melodies().map(\.id) == [first.id, second.id])
        #expect(pair.libraryB.melodies().map(\.id) == [first.id, second.id])
        #expect(try pair.libraryB.musicXML(for: first.id) == MusicXMLFixtures.simpleFourMeasures)
    }

    @Test("manual selection stays on the Mac that chose it")
    func selectionStaysLocal() throws {
        let pair = try makePair()
        defer { try? FileManager.default.removeItem(at: pair.root) }

        guard case .imported(let first, _) = pair.libraryA.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("first import failed")
            return
        }
        guard case .imported(let second, _) = pair.libraryA.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("second import failed")
            return
        }
        try pair.libraryA.select(id: second.id)
        pair.libraryB.reload()

        #expect(pair.libraryA.selectedMelodyID == second.id)
        #expect(pair.libraryB.selectedMelodyID == nil)
        #expect(pair.libraryB.currentMelody() == nil)
        #expect(first.id != second.id)
    }

    @Test("a later rename wins, and a delete wins over a later rename")
    func laterRenameWinsUntilDeleted() throws {
        let pair = try makePair()
        defer { try? FileManager.default.removeItem(at: pair.root) }

        guard case .imported(let melody, _) = pair.libraryA.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("import failed")
            return
        }
        pair.libraryB.reload()

        pair.clockA.advance(10)
        try pair.libraryA.rename(id: melody.id, to: "甲")
        pair.clockB.advance(20)
        try pair.libraryB.rename(id: melody.id, to: "乙")
        pair.libraryA.reload()
        pair.libraryB.reload()
        #expect(pair.libraryA.melodies().first?.title == "乙")
        #expect(pair.libraryB.melodies().first?.title == "乙")

        pair.clockB.advance(5)
        try pair.libraryB.rename(id: melody.id, to: "丙")
        pair.clockA.advance(1)
        try pair.libraryA.delete(id: melody.id)
        pair.libraryA.reload()
        pair.libraryB.reload()
        #expect(pair.libraryA.melodies().isEmpty)
        #expect(pair.libraryB.melodies().isEmpty)
    }

    @Test("the melody that took a title later is given a numeric suffix")
    func duplicateTitlesGainSuffix() throws {
        let pair = try makePair()
        defer { try? FileManager.default.removeItem(at: pair.root) }

        guard case .imported = pair.libraryA.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("first import failed")
            return
        }
        guard case .imported = pair.libraryB.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("second import failed")
            return
        }
        pair.libraryA.reload()
        pair.libraryB.reload()

        #expect(pair.libraryA.melodies().map(\.title) == ["未命名旋律", "未命名旋律 2"])
        #expect(pair.libraryB.melodies().map(\.title) == ["未命名旋律", "未命名旋律 2"])
    }

    @Test("a file dropped into the library folder is not a melody")
    func finderDropIsIgnored() throws {
        let pair = try makePair()
        defer { try? FileManager.default.removeItem(at: pair.root) }

        let shared = pair.root.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let dropped = shared.appendingPathComponent("小星星.musicxml")
        try MusicXMLFixtures.simpleFourMeasures.write(to: dropped, atomically: true, encoding: .utf8)

        pair.libraryA.reload()
        #expect(pair.libraryA.melodies().isEmpty)
    }

    @Test("a private library is folded into the shared library once, then retired")
    func privateLibraryFoldsInOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("melody-fold-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let shared = root.appendingPathComponent("shared", isDirectory: true)
        let privateDir = root.appendingPathComponent("private", isDirectory: true)
        let local = root.appendingPathComponent("local", isDirectory: true)
        let reachability = Reachability(false)
        let clock = Clock(Date(timeIntervalSince1970: 1_700_000_000))
        let library = MelodyLibrary(
            sharedDirectory: shared,
            privateDirectory: privateDir,
            localStateDirectory: local,
            sharedContainerIsReachable: { reachability.value },
            now: { clock.now() }
        )

        guard case .imported(let melody, _) = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("import failed")
            return
        }
        #expect(library.currentResidence == .privateLibrary)
        #expect(library.residenceSummary == "曲库只在这台 Mac 上。iCloud 云盘不可用，其他 Mac 看不到这里的旋律。")

        reachability.value = true
        library.reload()
        #expect(library.currentResidence == .shared)
        #expect(library.residenceSummary == "曲库在 iCloud 云盘，同一 Apple ID 的 Mac 会保持一致。")
        #expect(library.melodies().map(\.id) == [melody.id])
        #expect(library.selectedMelodyID == melody.id)

        reachability.value = false
        library.reload()
        #expect(library.melodies().isEmpty)
        #expect(library.currentMelody() == nil)
        #expect(library.selectedMelodyID == melody.id)

        reachability.value = true
        library.reload()
        #expect(library.melodies().map(\.id) == [melody.id])
        #expect(library.currentMelody()?.id == melody.id)
        #expect(try library.musicXML(for: melody.id) == MusicXMLFixtures.simpleFourMeasures)
    }

    @Test("an old manifest's selection stays on this Mac and its melodies join the shared library")
    func legacyManifestFoldsWithoutSharingSelection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("melody-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let shared = root.appendingPathComponent("shared", isDirectory: true)
        let privateDir = root.appendingPathComponent("private", isDirectory: true)
        let localA = root.appendingPathComponent("local-a", isDirectory: true)
        let localB = root.appendingPathComponent("local-b", isDirectory: true)
        let melodyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        try FileManager.default.createDirectory(
            at: privateDir.appendingPathComponent("scores", isDirectory: true),
            withIntermediateDirectories: true
        )
        try MusicXMLFixtures.twoMeasures.write(
            to: privateDir.appendingPathComponent("scores/\(melodyID.uuidString).musicxml"),
            atomically: true,
            encoding: .utf8
        )
        let manifest = """
        {"melodies":[{"id":"\(melodyID.uuidString)","measureCount":2,"title":"小星星"}],"selectedMelodyID":"\(melodyID.uuidString)"}
        """
        try manifest.write(
            to: privateDir.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let libraryA = MelodyLibrary(
            sharedDirectory: shared,
            privateDirectory: privateDir,
            localStateDirectory: localA,
            sharedContainerIsReachable: { true }
        )
        let libraryB = MelodyLibrary(
            sharedDirectory: shared,
            privateDirectory: root.appendingPathComponent("private-b", isDirectory: true),
            localStateDirectory: localB,
            sharedContainerIsReachable: { true }
        )

        #expect(libraryA.melodies().map(\.title) == ["小星星"])
        #expect(libraryA.selectedMelodyID == melodyID)
        #expect(libraryB.melodies().map(\.title) == ["小星星"])
        #expect(libraryB.selectedMelodyID == nil)
        #expect(try libraryB.musicXML(for: melodyID) == MusicXMLFixtures.twoMeasures)
    }
}
