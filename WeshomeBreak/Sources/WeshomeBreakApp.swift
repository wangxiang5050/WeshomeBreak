import GrillBreakCore
import SwiftUI

@main
struct WeshomeBreakApp: App {
    @StateObject private var schedulerController: BreakSchedulerController
    @StateObject private var settingsStore: BreakSettingsStore
    @StateObject private var melodyLibraryStore: MelodyLibraryStore
    private let restOverlay: RestOverlay
    private let menuStatusTitleUpdater: MenuBarLiveStatusTitleUpdater
    private let availableSceneModes: [BreakSceneMode]

    init() {
        let settingsStore = BreakSettingsStore()
        let melodyLibrary = MelodyLibrary(rootDirectory: AppPaths.melodyLibraryRoot)
        let melodyLibraryStore = MelodyLibraryStore(library: melodyLibrary)
        let sceneModes: [BreakSceneMode] = [
            StaffMelodySceneMode(library: melodyLibrary)
        ]
        let controller = BreakSchedulerController(settingsStore: settingsStore)

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _melodyLibraryStore = StateObject(wrappedValue: melodyLibraryStore)
        _schedulerController = StateObject(wrappedValue: controller)
        availableSceneModes = sceneModes
        restOverlay = RestOverlay(
            settingsStore: settingsStore,
            sceneModeRegistry: BreakSceneModeRegistry(modes: sceneModes),
            windows: BreakOverlayManager(
                schedulerController: controller,
                settingsStore: settingsStore
            )
        )
        restOverlay.start(observing: controller)
        menuStatusTitleUpdater = MenuBarLiveStatusTitleUpdater(schedulerController: controller)
        menuStatusTitleUpdater.start()
    }

    var body: some Scene {
        MenuBarExtra("Weshome Break", systemImage: "cup.and.saucer.fill") {
            MenuBarContentView(schedulerController: schedulerController)
        }
        .menuBarExtraStyle(.menu)

        Window("设置", id: "settings") {
            SettingsView(
                settingsStore: settingsStore,
                melodyLibraryStore: melodyLibraryStore,
                availableSceneModes: availableSceneModes
            )
        }
        .windowResizability(.contentSize)
    }
}
