import Combine
import Foundation
import GrillBreakCore

/// Watches the scheduler's phase and keeps the full-screen overlay in sync:
/// presents it the moment the scheduler enters `.resting`, dismisses it the
/// moment the scheduler leaves `.resting`. Each time it presents, it asks
/// its `BreakSceneModeRegistry` for the mode to show this rest — for now
/// that registry only has one mode registered (ticket 06), with the
/// fixed-vs-random selection strategy itself becoming user-configurable in
/// ticket 07's settings panel.
@MainActor
final class BreakOverlayCoordinator {
    private let schedulerController: BreakSchedulerController
    private let overlayManager: BreakOverlayManager
    private var sceneModeRegistry: BreakSceneModeRegistry
    private var cancellable: AnyCancellable?

    init(
        schedulerController: BreakSchedulerController,
        overlayManager: BreakOverlayManager? = nil,
        sceneModeRegistry: BreakSceneModeRegistry = BreakSceneModeRegistry(modes: [StaffNotesSceneMode()])
    ) {
        self.schedulerController = schedulerController
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
            let mode = sceneModeRegistry.selectMode(using: .randomNoRepeat)
                ?? sceneModeRegistry.registeredModes.first
            guard let mode else { return }
            overlayManager.present(schedulerController: schedulerController, sceneMode: mode)
        case .working:
            overlayManager.dismiss()
        }
    }
}
