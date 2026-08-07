import GrillBreakCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var schedulerController: BreakSchedulerController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)

        Button(schedulerController.isPaused ? "继续" : "暂停") {
            schedulerController.togglePause()
        }

        Button("立即开始一次休息") {
            schedulerController.startBreakNow()
        }
        .disabled(schedulerController.phase == .resting || schedulerController.isPaused)

        Divider()

        Button("设置…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }

        Divider()

        Button("退出 App") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusLine: String {
        let phaseName: String
        switch schedulerController.phase {
        case .working: phaseName = "工作中"
        case .resting: phaseName = "休息中"
        }
        let label = schedulerController.isPaused ? "已暂停" : phaseName
        return "\(label) · 剩余 \(schedulerController.formattedRemaining)"
    }
}
