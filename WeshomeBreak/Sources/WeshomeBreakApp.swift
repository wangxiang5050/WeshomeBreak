import SwiftUI

@main
struct WeshomeBreakApp: App {
    @StateObject private var schedulerController: BreakSchedulerController
    private let overlayCoordinator: BreakOverlayCoordinator

    init() {
        let controller = BreakSchedulerController()
        _schedulerController = StateObject(wrappedValue: controller)
        overlayCoordinator = BreakOverlayCoordinator(schedulerController: controller)
        overlayCoordinator.start()
    }

    var body: some Scene {
        MenuBarExtra("Weshome Break", systemImage: "cup.and.saucer.fill") {
            MenuBarContentView(schedulerController: schedulerController)
        }
        .menuBarExtraStyle(.menu)
    }
}
