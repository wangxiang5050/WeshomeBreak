import GrillBreakCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var schedulerController: BreakSchedulerController

    var body: some View {
        Text(statusLine)

        Button(schedulerController.isPaused ? "继续" : "暂停") {
            schedulerController.togglePause()
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
