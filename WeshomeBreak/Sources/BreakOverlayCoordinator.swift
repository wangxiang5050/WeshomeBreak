import Combine
import Foundation
import GrillBreakCore

/// Watches the scheduler's phase and keeps the full-screen overlay in sync:
/// presents it the moment the scheduler enters `.resting`, dismisses it the
/// moment the scheduler leaves `.resting`. Each time it presents, it asks
/// its `BreakSceneModeRegistry` for the mode to show this rest, using
/// whichever selection strategy (fixed mode / random rotation) is currently
/// configured in the settings panel — read fresh at selection time, so a
/// change to that setting takes effect starting with the very next rest.
@MainActor
final class BreakOverlayCoordinator {
    private let schedulerController: BreakSchedulerController
    private let overlayManager: BreakOverlayManager
    private let settingsStore: BreakSettingsStore
    private var sceneModeRegistry: BreakSceneModeRegistry
    private var cancellable: AnyCancellable?

    init(
        schedulerController: BreakSchedulerController,
        settingsStore: BreakSettingsStore,
        overlayManager: BreakOverlayManager? = nil,
        sceneModeRegistry: BreakSceneModeRegistry = BreakSceneModeRegistry(modes: [StaffNotesSceneMode()])
    ) {
        self.schedulerController = schedulerController
        self.settingsStore = settingsStore
        self.overlayManager = overlayManager ?? BreakOverlayManager()
        self.sceneModeRegistry = sceneModeRegistry
    }

    /// Starts observing phase changes. Call once, e.g. from the app's
    /// `init`, after the scheduler controller has been created.
    func start() {
        syncOverlay(for: schedulerController.phase)
        cancellable = schedulerController.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                self?.syncOverlay(for: phase)
            }
    }

    private func syncOverlay(for phase: BreakPhase) {
        switch phase {
        case .resting:
            let mode = sceneModeRegistry.selectMode(using: settingsStore.sceneModeSelectionStrategy)
                ?? sceneModeRegistry.registeredModes.first
            guard let mode else { return }
            overlayManager.present(schedulerController: schedulerController, sceneMode: mode, settingsStore: settingsStore)
        case .working:
            overlayManager.dismiss()
        }
    }
}
