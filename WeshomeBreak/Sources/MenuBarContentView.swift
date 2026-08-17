import GrillBreakCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var breakCycle: BreakCycle
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status is a non-interactive header. Per-second remaining ticks must
        // not republish through `BreakCycle` or this menu is rebuilt while
        // open and NSMenu hover highlight drifts. Live title updates while
        // open are handled by `MenuBarLiveStatusTitleUpdater`.
        Text(breakCycle.statusLine)

        Button(breakCycle.isPaused ? MenuBarCopy.resume : MenuBarCopy.pause) {
            breakCycle.togglePause()
        }

        Button(MenuBarCopy.startBreakNow) {
            breakCycle.startBreakNow()
        }
        .disabled(breakCycle.phase == .resting || breakCycle.isPaused)

        Divider()

        Button(MenuBarCopy.settings) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }

        Divider()

        Button(MenuBarCopy.quit) {
            NSApplication.shared.terminate(nil)
        }
    }
}
