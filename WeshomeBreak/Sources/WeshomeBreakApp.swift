import SwiftUI

@main
struct WeshomeBreakApp: App {
    @StateObject private var schedulerController = BreakSchedulerController()

    var body: some Scene {
        MenuBarExtra("Weshome Break", systemImage: "cup.and.saucer.fill") {
            MenuBarContentView(schedulerController: schedulerController)
        }
        .menuBarExtraStyle(.menu)
    }
}
