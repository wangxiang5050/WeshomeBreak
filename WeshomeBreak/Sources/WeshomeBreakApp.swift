import GrillBreakCore
import SwiftUI

@main
struct WeshomeBreakApp: App {
    @StateObject private var breakCycle: BreakCycle
    @StateObject private var settingsStore: BreakSettingsStore
    @StateObject private var melodyLibraryStore: MelodyLibraryStore
    private let melodyLibrary: MelodyLibrary
    private let restOverlay: RestOverlay
    private let menuStatusTitleUpdater: MenuBarLiveStatusTitleUpdater
    private let availableSceneModes: [BreakSceneMode]

    init() {
        let settingsStore = BreakSettingsStore()
        let melodyLibrary = MelodyLibrary(rootDirectory: AppPaths.melodyLibraryRoot)
        let melodyLibraryStore = MelodyLibraryStore(library: melodyLibrary)
        let sceneModes: [BreakSceneMode] = [
            StaffMelodySceneMode(library: melodyLibrary, settingsStore: settingsStore)
        ]
        let breakCycle = BreakCycle(settingsStore: settingsStore)

        self.melodyLibrary = melodyLibrary
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _melodyLibraryStore = StateObject(wrappedValue: melodyLibraryStore)
        _breakCycle = StateObject(wrappedValue: breakCycle)
        availableSceneModes = sceneModes
        restOverlay = RestOverlay(
            settingsStore: settingsStore,
            sceneModeRegistry: BreakSceneModeRegistry(modes: sceneModes),
            windows: BreakOverlayManager(
                breakCycle: breakCycle,
                settingsStore: settingsStore
            )
        )
        restOverlay.start(observing: breakCycle)
        menuStatusTitleUpdater = MenuBarLiveStatusTitleUpdater(breakCycle: breakCycle)
        menuStatusTitleUpdater.start()
    }

    var body: some Scene {
        MenuBarExtra("Weshome Break", systemImage: "cup.and.saucer.fill") {
            MenuBarContentView(breakCycle: breakCycle)
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

        // Independent of the settings window's lifecycle: closing Settings
        // does not close an open Melody Preview, and vice versa.
        Window("旋律预览", id: SettingsView.melodyPreviewWindowID) {
            MelodyPreviewView(
                library: melodyLibrary,
                melodyLibraryStore: melodyLibraryStore,
                settingsStore: settingsStore
            )
            .frame(minWidth: 360, idealWidth: 640, minHeight: 260, idealHeight: 480)
        }
    }
}
