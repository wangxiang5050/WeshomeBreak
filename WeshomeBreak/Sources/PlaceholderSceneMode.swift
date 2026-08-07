import GrillBreakCore
import SwiftUI

/// Temporary `BreakSceneMode` registered until Staff Melody Scene (ticket 12)
/// lands. Keeps the protocol → registry → overlay path end-to-end demoable
/// without the old decorative flying-notes visual.
struct PlaceholderSceneMode: BreakSceneMode {
    let identifier = "placeholder"
    let displayName = "占位模式"

    @MainActor
    func makeView() -> AnyView {
        AnyView(PlaceholderSceneView())
    }
}

/// Calm full-screen stand-in behind the countdown: no musical content yet.
private struct PlaceholderSceneView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.09, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Text("休息中")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
        }
        .ignoresSafeArea()
    }
}
