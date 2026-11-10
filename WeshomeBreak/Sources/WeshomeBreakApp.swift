import GrillBreakCore
import SwiftUI

@main
struct WeshomeBreakApp: App {
    @StateObject private var breakCycle: BreakCycle
    @StateObject private var settingsStore: BreakSettingsStore
    @StateObject private var melodyLibraryStore: MelodyLibraryStore
    private let melodyLibrary: MelodyLibrary
    private let melodyLibraryWatcher: MelodyLibraryDirectoryWatcher
    private let restOverlay: RestOverlay
    private let menuStatusTitleUpdater: MenuBarLiveStatusTitleUpdater
    private let loginLaunch: LoginLaunchController
    private let availableSceneModes: [BreakSceneMode]

    init() {
        let settingsStore = BreakSettingsStore()
        let melodyLibrary = MelodyLibrary(
            sharedDirectory: AppPaths.sharedMelodyLibraryDirectory,
            privateDirectory: AppPaths.privateMelodyLibraryRoot,
            localStateDirectory: AppPaths.melodyLibraryLocalStateRoot,
            sharedContainerIsReachable: AppPaths.iCloudDriveIsReachable
        )
        let melodyLibraryStore = MelodyLibraryStore(library: melodyLibrary)
        let melodyLibraryWatcher = MelodyLibraryDirectoryWatcher {
            melodyLibraryStore.reloadFromDisk()
        }
        let breakCycle = BreakCycle(settingsStore: settingsStore)
        let sceneModes: [BreakSceneMode] = [
            StaffMelodySceneMode(
                library: melodyLibrary,
                melodyLibraryStore: melodyLibraryStore,
                settingsStore: settingsStore,
                breakCycle: breakCycle,
                selectionState: MelodySelectionState(
                    lastShownMelodyID: settingsStore.lastShownMelodyID
                )
            )
        ]

        let loginLaunch = LoginLaunchController()

        self.melodyLibrary = melodyLibrary
        self.melodyLibraryWatcher = melodyLibraryWatcher
        self.loginLaunch = loginLaunch
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
        loginLaunch.apply(enabled: settingsStore.launchAtLogin)
        melodyLibraryWatcher.start()
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
                loginLaunch: loginLaunch,
                availableSceneModes: availableSceneModes
            )
        }
        // Resizable between the form's minimum and the screen. `.contentSize`
        // locked Settings to the form's ideal size, so the edges could not be dragged.
        .windowResizability(.automatic)

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
