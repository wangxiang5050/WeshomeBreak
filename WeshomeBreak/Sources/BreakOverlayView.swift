import GrillBreakCore
import SwiftUI

/// The full-screen break overlay's content: the current `BreakSceneMode`'s
/// visual filling the screen, a remaining-time countdown in the corner, and
/// a hover control bar (scene chrome + skip/delay) that stays hidden until
/// the mouse moves — like a video player's controls — so it never distracts
/// from the break visual.
struct BreakOverlayView: View {
    @ObservedObject var breakCycle: BreakCycle
    @ObservedObject private var remaining: BreakCycle.Remaining
    let sceneMode: BreakSceneMode
    @ObservedObject var settingsStore: BreakSettingsStore
    @ObservedObject var sceneSession: BreakSceneSession

    /// Whether the skip/delay control bar is currently visible. Flips to
    /// `true` on any mouse movement over the overlay, then automatically
    /// flips back to `false` after `controlBarAutoHideDelay` of no further
    /// movement — mirroring how video player controls behave.
    @State private var isControlBarVisible = false
    @State private var autoHideGeneration = 0

    private static let controlBarAutoHideDelay: Duration = .seconds(2.5)

    init(
        breakCycle: BreakCycle,
        sceneMode: BreakSceneMode,
        settingsStore: BreakSettingsStore,
        sceneSession: BreakSceneSession
    ) {
        self.breakCycle = breakCycle
        self._remaining = ObservedObject(wrappedValue: breakCycle.remaining)
        self.sceneMode = sceneMode
        self.settingsStore = settingsStore
        self.sceneSession = sceneSession
    }

    private var showsHoverBar: Bool {
        sceneSession.hoverBarExtraTitle != nil
            || settingsStore.allowSkip
            || settingsStore.allowDelay
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            sceneMode.makeView(session: sceneSession)
                .ignoresSafeArea()

            Text(remaining.formatted)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            if showsHoverBar {
                controlBar
                    .opacity(isControlBarVisible ? 1 : 0)
                    .allowsHitTesting(isControlBarVisible)
                    .animation(.easeInOut(duration: 0.2), value: isControlBarVisible)
            }
        }
        .onContinuousHover { phase in
            if case .active = phase {
                revealControlBarTemporarily()
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            if let title = sceneSession.hoverBarExtraTitle {
                Button(title) {
                    sceneSession.performHoverBarExtra()
                }
            }
            if settingsStore.allowSkip {
                Button("跳过本次休息") {
                    breakCycle.skipBreak()
                }
            }
            if settingsStore.allowDelay {
                Button("延迟休息") {
                    breakCycle.delayBreak()
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.bottom, 40)
    }

    private func revealControlBarTemporarily() {
        isControlBarVisible = true
        autoHideGeneration += 1
        let generation = autoHideGeneration
        Task {
            try? await Task.sleep(for: Self.controlBarAutoHideDelay)
            if generation == autoHideGeneration {
                isControlBarVisible = false
            }
        }
    }
}
