import GrillBreakCore
import SwiftUI

/// The full-screen break overlay's content: the current `BreakSceneMode`'s
/// visual filling the screen, a remaining-time countdown in the corner, and
/// a skip/delay/Staff Melody Visibility control bar that stays hidden until
/// the mouse moves — like a video player's controls — so it never distracts
/// from the break visual.
struct BreakOverlayView: View {
    @ObservedObject var schedulerController: BreakSchedulerController
    let sceneMode: BreakSceneMode
    @ObservedObject var settingsStore: BreakSettingsStore

    /// Whether the skip/delay control bar is currently visible. Flips to
    /// `true` on any mouse movement over the overlay, then automatically
    /// flips back to `false` after `controlBarAutoHideDelay` of no further
    /// movement — mirroring how video player controls behave.
    @State private var isControlBarVisible = false
    @State private var autoHideGeneration = 0
    /// Session-scoped for this break presentation; a new overlay starts visible.
    @State private var staffMelodyVisibility = StaffMelodyVisibility()

    private static let controlBarAutoHideDelay: Duration = .seconds(2.5)

    private var controlBarPolicy: BreakOverlayControlBarPolicy {
        BreakOverlayControlBarPolicy(
            allowSkip: settingsStore.allowSkip,
            allowDelay: settingsStore.allowDelay,
            sceneModeIdentifier: sceneMode.identifier
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            sceneMode.makeView()
                .environment(\.staffMelodyContentVisible, staffMelodyVisibility.isContentVisible)
                .ignoresSafeArea()

            Text(schedulerController.formattedRemaining)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            if controlBarPolicy.shouldShowControlBar {
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
            if controlBarPolicy.showsStaffMelodyVisibilityToggle {
                Button(staffMelodyVisibility.toggleTitle) {
                    staffMelodyVisibility.toggle()
                }
            }
            if controlBarPolicy.showsSkip {
                Button("跳过本次休息") {
                    schedulerController.skipBreak()
                }
            }
            if controlBarPolicy.showsDelay {
                Button("延迟休息") {
                    schedulerController.delayBreak()
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
