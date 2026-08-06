import SwiftUI

/// Placeholder content for the full-screen break overlay.
///
/// This is intentionally *not* the final "音符沿五线谱飘入" visual — that
/// lives behind the `BreakSceneMode` protocol and lands in a later ticket.
/// For now this just proves the overlay window mechanics work end to end:
/// dark background, remaining-time countdown in the corner, plus the
/// skip/delay control bar that stays hidden until the mouse moves — like a
/// video player's controls — so it never distracts from the break visual.
struct BreakOverlayView: View {
    @ObservedObject var schedulerController: BreakSchedulerController

    /// Whether the skip/delay control bar is currently visible. Flips to
    /// `true` on any mouse movement over the overlay, then automatically
    /// flips back to `false` after `controlBarAutoHideDelay` of no further
    /// movement — mirroring how video player controls behave.
    @State private var isControlBarVisible = false
    @State private var autoHideGeneration = 0

    private static let controlBarAutoHideDelay: Duration = .seconds(2.5)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Text("休息一下")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                Text("放松片刻,马上回来")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(schedulerController.formattedRemaining)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            controlBar
                .opacity(isControlBarVisible ? 1 : 0)
                .allowsHitTesting(isControlBarVisible)
                .animation(.easeInOut(duration: 0.2), value: isControlBarVisible)
        }
        .onContinuousHover { phase in
            if case .active = phase {
                revealControlBarTemporarily()
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button("跳过本次休息") {
                schedulerController.skipBreak()
            }
            Button("延迟休息") {
                schedulerController.delayBreak()
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
