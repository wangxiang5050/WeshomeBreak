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
