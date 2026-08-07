import GrillBreakCore
import SwiftUI

@main
struct WeshomeBreakApp: App {
    @StateObject private var schedulerController: BreakSchedulerController
    @StateObject private var settingsStore: BreakSettingsStore
    private let overlayCoordinator: BreakOverlayCoordinator
    private let availableSceneModes: [BreakSceneMode]

    init() {
        let settingsStore = BreakSettingsStore()
        let melodyLibrary = MelodyLibrary(rootDirectory: AppPaths.melodyLibraryRoot)
        let sceneModes: [BreakSceneMode] = [
            StaffMelodySceneMode(library: melodyLibrary)
        ]
        let controller = BreakSchedulerController(settingsStore: settingsStore)

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _schedulerController = StateObject(wrappedValue: controller)
        availableSceneModes = sceneModes
        overlayCoordinator = BreakOverlayCoordinator(
            schedulerController: controller,
            settingsStore: settingsStore,
            sceneModeRegistry: BreakSceneModeRegistry(modes: sceneModes)
        )
        overlayCoordinator.start()
    }

    var body: some Scene {
        MenuBarExtra("Weshome Break", systemImage: "cup.and.saucer.fill") {
            MenuBarContentView(schedulerController: schedulerController)
        }
        .menuBarExtraStyle(.menu)

        Window("设置", id: "settings") {
            SettingsView(settingsStore: settingsStore, availableSceneModes: availableSceneModes)
        }
        .windowResizability(.contentSize)
    }
}
