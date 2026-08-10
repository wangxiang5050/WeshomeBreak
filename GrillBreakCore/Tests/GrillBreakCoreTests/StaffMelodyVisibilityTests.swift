import Foundation
import Testing
@testable import GrillBreakCore

@Suite("StaffMelodyVisibility")
struct StaffMelodyVisibilityTests {

    @Test("new session starts with content visible")
    func newSessionStartsVisible() {
        let visibility = StaffMelodyVisibility()
        #expect(visibility.isContentVisible)
    }

    @Test("toggle flips content visibility")
    func toggleFlipsVisibility() {
        var visibility = StaffMelodyVisibility()
        visibility.toggle()
        #expect(!visibility.isContentVisible)
        visibility.toggle()
        #expect(visibility.isContentVisible)
    }

    @Test("toggle title asks to hide when content is visible")
    func toggleTitleWhenVisible() {
        let visibility = StaffMelodyVisibility(isContentVisible: true)
        #expect(visibility.toggleTitle == "隐藏旋律")
    }

    @Test("toggle title asks to show when content is hidden")
    func toggleTitleWhenHidden() {
        let visibility = StaffMelodyVisibility(isContentVisible: false)
        #expect(visibility.toggleTitle == "显示旋律")
    }

    @Test("staff melody scene identifier supports visibility toggle")
    func staffMelodySceneSupportsToggle() {
        #expect(StaffMelodyVisibility.supports(sceneModeIdentifier: StaffMelodyVisibility.sceneModeIdentifier))
        #expect(StaffMelodyVisibility.sceneModeIdentifier == "staff-melody")
    }

    @Test("other scene modes do not support visibility toggle")
    func otherScenesDoNotSupportToggle() {
        #expect(!StaffMelodyVisibility.supports(sceneModeIdentifier: "other-mode"))
    }
}

@Suite("BreakOverlayControlBarPolicy")
struct BreakOverlayControlBarPolicyTests {

    @Test("control bar is hidden when skip, delay, and staff melody toggle are all unavailable")
    func hiddenWhenNothingToShow() {
        let policy = BreakOverlayControlBarPolicy(
            allowSkip: false,
            allowDelay: false,
            sceneModeIdentifier: "other-mode"
        )
        #expect(!policy.showsSkip)
        #expect(!policy.showsDelay)
        #expect(!policy.showsStaffMelodyVisibilityToggle)
        #expect(!policy.shouldShowControlBar)
    }

    @Test("staff melody scene shows visibility toggle even when skip and delay are disabled")
    func staffMelodyToggleWithoutSkipDelay() {
        let policy = BreakOverlayControlBarPolicy(
            allowSkip: false,
            allowDelay: false,
            sceneModeIdentifier: StaffMelodyVisibility.sceneModeIdentifier
        )
        #expect(policy.showsStaffMelodyVisibilityToggle)
        #expect(policy.shouldShowControlBar)
        #expect(!policy.showsSkip)
        #expect(!policy.showsDelay)
    }

    @Test("skip and delay flags pass through independently of scene mode")
    func skipAndDelayPassThrough() {
        let policy = BreakOverlayControlBarPolicy(
            allowSkip: true,
            allowDelay: true,
            sceneModeIdentifier: "other-mode"
        )
        #expect(policy.showsSkip)
        #expect(policy.showsDelay)
        #expect(!policy.showsStaffMelodyVisibilityToggle)
        #expect(policy.shouldShowControlBar)
    }
}
