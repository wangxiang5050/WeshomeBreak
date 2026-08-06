import SwiftUI

/// Placeholder content for the full-screen break overlay.
///
/// This is intentionally *not* the final "音符沿五线谱飘入" visual — that
/// lives behind the `BreakSceneMode` protocol and lands in a later ticket.
/// For now this just proves the overlay window mechanics work end to end:
/// dark background, remaining-time countdown in the corner.
struct BreakOverlayView: View {
    @ObservedObject var schedulerController: BreakSchedulerController

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
        }
    }
}
