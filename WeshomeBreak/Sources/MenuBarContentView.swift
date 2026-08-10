import GrillBreakCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var schedulerController: BreakSchedulerController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status is a non-interactive header. Per-second remaining ticks must
        // not republish through `BreakSchedulerController` or this menu is
        // rebuilt while open and NSMenu hover highlight drifts. Live title
        // updates while open are handled by `MenuBarLiveStatusTitleUpdater`.
        Text(schedulerController.menuStatusLine)

        Button(schedulerController.isPaused ? MenuBarCopy.resume : MenuBarCopy.pause) {
            schedulerController.togglePause()
        }

        Button(MenuBarCopy.startBreakNow) {
            schedulerController.startBreakNow()
        }
        .disabled(schedulerController.phase == .resting || schedulerController.isPaused)

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
