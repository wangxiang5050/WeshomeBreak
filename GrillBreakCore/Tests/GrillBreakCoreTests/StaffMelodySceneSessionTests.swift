import Foundation
import Testing
@testable import GrillBreakCore

@Suite("StaffMelodySceneSession")
@MainActor
struct StaffMelodySceneSessionTests {

    @Test("new session starts with content visible and hide title")
    func newSessionStartsVisible() {
        let session = StaffMelodySceneSession()
        #expect(session.showsContent)
        #expect(session.hoverBarExtraTitle == "隐藏旋律")
    }

    @Test("extra control toggles visibility and title")
    func extraControlTogglesVisibility() {
        let session = StaffMelodySceneSession()
        session.performHoverBarExtra()
        #expect(!session.showsContent)
        #expect(session.hoverBarExtraTitle == "显示旋律")
        session.performHoverBarExtra()
        #expect(session.showsContent)
        #expect(session.hoverBarExtraTitle == "隐藏旋律")
    }

    @Test("a new session starts visible even after a previous session was hidden")
    func newSessionStartsVisibleAfterPreviousWasHidden() {
        let previous = StaffMelodySceneSession()
        previous.performHoverBarExtra()
        #expect(!previous.showsContent)

        let next = StaffMelodySceneSession()
        #expect(next.showsContent)
        #expect(next.hoverBarExtraTitle == "隐藏旋律")
    }

    @Test("a melody that leaves during the rest is replaced on this rest's page")
    func melodyThatLeavesDuringRestIsReplaced() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-rest-replaced-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = MelodyLibrary(rootDirectory: root)
        guard case .imported(let held, _) = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("expected the held melody to import")
            return
        }
        guard case .imported(let replacement, _) = library.importMusicXML(MusicXMLFixtures.twoMeasures) else {
            Issue.record("expected the replacement melody to import")
            return
        }

        let selection = MelodySelectionState(randomIndex: { _ in 0 })
        let session = StaffMelodySceneSession()
        session.beginRest(
            in: library,
            using: .manual(melodyID: held.id),
            continuingSameRest: false,
            selection: selection,
            scalePercent: 60,
            durationProportionPercent: 60
        )
        #expect(session.melodyID == held.id)

        try library.delete(id: held.id)
        session.libraryChanged(in: library)

        #expect(session.melodyID == replacement.id)
        #expect(selection.lastShownMelodyID == replacement.id)
        guard case .ready(let html) = session.page else {
            Issue.record("expected the replacement page, got \(session.page)")
            return
        }
        let replacementScore = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: MusicXMLSystemBreakLayout.measuresPerSystem,
            to: MusicXMLFixtures.twoMeasures
        )
        let heldScore = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: MusicXMLSystemBreakLayout.measuresPerSystem,
            to: MusicXMLFixtures.simpleFourMeasures
        )
        #expect(html.contains(Data(replacementScore.utf8).base64EncodedString()))
        #expect(!html.contains(Data(heldScore.utf8).base64EncodedString()))
    }

    @Test("a score that arrives during the rest keeps this melody and becomes readable")
    func scoreArrivingDuringRestKeepsTheMelody() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-rest-arrives-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = MelodyLibrary(rootDirectory: root)
        guard case .imported(let melody, _) = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures) else {
            Issue.record("expected the melody to import")
            return
        }
        let scoreURL = root.appendingPathComponent("scores/\(melody.id.uuidString).musicxml")
        let score = try String(contentsOf: scoreURL, encoding: .utf8)
        try FileManager.default.removeItem(at: scoreURL)

        let session = StaffMelodySceneSession()
        session.beginRest(
            in: library,
            using: .manual(melodyID: melody.id),
            continuingSameRest: false,
            selection: MelodySelectionState(randomIndex: { _ in 0 }),
            scalePercent: 60,
            durationProportionPercent: 60
        )
        #expect(session.melodyID == melody.id)
        #expect(session.page == .failed(message: "这份旋律还不能读。若刚从另一台 Mac 同步，请稍候，不要再次导入。"))

        try score.write(to: scoreURL, atomically: true, encoding: .utf8)
        session.libraryChanged(in: library)

        #expect(session.melodyID == melody.id)
        guard case .ready(let html) = session.page else {
            Issue.record("expected a readable page, got \(session.page)")
            return
        }
        let laidOut = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: MusicXMLSystemBreakLayout.measuresPerSystem,
            to: MusicXMLFixtures.simpleFourMeasures
        )
        #expect(html.contains(Data(laidOut.utf8).base64EncodedString()))
    }

    @Test("an empty rest stays empty when the library gains a melody")
    func emptyRestStaysEmptyWhenLibraryGainsAMelody() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-rest-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = MelodyLibrary(rootDirectory: root)
        let selection = MelodySelectionState(
            lastShownMelodyID: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
            randomIndex: { _ in 0 }
        )
        let session = StaffMelodySceneSession()
        session.beginRest(
            in: library,
            using: .manual(melodyID: nil),
            continuingSameRest: false,
            selection: selection,
            scalePercent: 60,
            durationProportionPercent: 60
        )
        #expect(session.melodyID == nil)
        #expect(session.page == .empty)

        _ = library.importMusicXML(MusicXMLFixtures.twoMeasures)
        session.libraryChanged(in: library)

        #expect(session.melodyID == nil)
        #expect(session.page == .empty)
        #expect(selection.lastShownMelodyID == UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
    }
}

@Suite("BreakSceneSession")
@MainActor
struct BreakSceneSessionTests {

    @Test("inert session contributes no hover-bar extra")
    func inertSessionHasNoExtra() {
        let session = BreakSceneSession()
        #expect(session.hoverBarExtraTitle == nil)
        #expect(session.showsContent)
        session.performHoverBarExtra()
        #expect(session.hoverBarExtraTitle == nil)
        #expect(session.showsContent)
    }
}
