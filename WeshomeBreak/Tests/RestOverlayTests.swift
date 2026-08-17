import Foundation
import GrillBreakCore
import SwiftUI
import Testing
@testable import WeshomeBreak

@Suite("RestOverlay")
@MainActor
struct RestOverlayTests {

    @Test("resting presents the mode selected by the current Scene Mode Selection")
    func restingPresentsSelectedMode() {
        let windows = RecordingRestOverlayWindows()
        let overlay = makeOverlay(
            windows: windows,
            modeIdentifiers: ["alpha", "beta"],
            selecting: "beta"
        )

        overlay.sync(phase: .resting)

        #expect(windows.presentedIdentifiers == ["beta"])
    }

    @Test("working dismisses the covering")
    func workingDismisses() {
        let windows = RecordingRestOverlayWindows()
        let overlay = makeOverlay(
            windows: windows,
            modeIdentifiers: ["alpha"],
            selecting: "alpha"
        )

        overlay.sync(phase: .resting)
        overlay.sync(phase: .working)

        #expect(windows.dismissCount == 1)
        #expect(!windows.isPresenting)
    }

    @Test("resting while already presenting does not present again")
    func restingWhilePresentingIsNoOp() {
        let windows = RecordingRestOverlayWindows()
        let overlay = makeOverlay(
            windows: windows,
            modeIdentifiers: ["alpha", "beta"],
            selecting: "alpha"
        )

        overlay.sync(phase: .resting)
        overlay.sync(phase: .resting)

        #expect(windows.presentedIdentifiers == ["alpha"])
    }

    @Test("resting while already presenting does not re-select the scene mode")
    func restingWhilePresentingDoesNotReselect() {
        let windows = RecordingRestOverlayWindows()
        let suite = "rest-overlay-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = BreakSettingsStore(defaults: defaults)
        settings.sceneModeSelectionRaw = BreakSettingsStore.randomSelectionValue

        let modes = ["alpha", "beta"].map { StubMode(identifier: $0, displayName: $0) }
        let overlay = RestOverlay(
            settingsStore: settings,
            sceneModeRegistry: BreakSceneModeRegistry(modes: modes) { _ in 0 },
            windows: windows
        )

        overlay.sync(phase: .resting)
        overlay.sync(phase: .resting)
        overlay.sync(phase: .working)
        overlay.sync(phase: .resting)

        #expect(windows.presentedIdentifiers == ["alpha", "beta"])
    }

    @Test("resting with no registered modes does not present")
    func restingWithNoModesDoesNotPresent() {
        let windows = RecordingRestOverlayWindows()
        let overlay = makeOverlay(
            windows: windows,
            modeIdentifiers: [],
            selecting: "alpha"
        )

        overlay.sync(phase: .resting)

        #expect(windows.presentedIdentifiers.isEmpty)
        #expect(!windows.isPresenting)
    }

    @Test("unknown fixed selection falls back to the first registered mode")
    func unknownFixedSelectionFallsBackToFirstMode() {
        let windows = RecordingRestOverlayWindows()
        let overlay = makeOverlay(
            windows: windows,
            modeIdentifiers: ["alpha", "beta"],
            selecting: "missing"
        )

        overlay.sync(phase: .resting)

        #expect(windows.presentedIdentifiers == ["alpha"])
    }

    // MARK: - Helpers

    private struct StubMode: BreakSceneMode {
        let identifier: String
        let displayName: String

        @MainActor
        func makeView() -> AnyView { AnyView(EmptyView()) }
    }

    @MainActor
    private final class RecordingRestOverlayWindows: RestOverlayWindows {
        private(set) var presentedIdentifiers: [String] = []
        private(set) var dismissCount = 0
        private(set) var isPresenting = false

        func present(sceneMode: BreakSceneMode) {
            presentedIdentifiers.append(sceneMode.identifier)
            isPresenting = true
        }

        func dismiss() {
            dismissCount += 1
            isPresenting = false
        }
    }

    private func makeOverlay(
        windows: RecordingRestOverlayWindows,
        modeIdentifiers: [String],
        selecting identifier: String
    ) -> RestOverlay {
        let suite = "rest-overlay-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = BreakSettingsStore(defaults: defaults)
        settings.sceneModeSelectionRaw = identifier

        let modes = modeIdentifiers.map { StubMode(identifier: $0, displayName: $0) }
        return RestOverlay(
            settingsStore: settings,
            sceneModeRegistry: BreakSceneModeRegistry(modes: modes),
            windows: windows
        )
    }
}
