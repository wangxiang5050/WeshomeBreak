import Combine
import Foundation
import GrillBreakCore

/// Watches the scheduler's phase and keeps the full-screen overlay in sync:
/// presents it the moment the scheduler enters `.resting`, dismisses it the
/// moment the scheduler leaves `.resting`. This is the seam that will later
/// grow to consult `BreakSceneMode` selection (ticket 06) and the skip/delay
/// controls (ticket 05) — for now it only wires up ticket 04's plain
/// present/dismiss behavior.
@MainActor
final class BreakOverlayCoordinator {
    private let schedulerController: BreakSchedulerController
    private let overlayManager: BreakOverlayManager
    private var cancellable: AnyCancellable?

    init(
        schedulerController: BreakSchedulerController,
        overlayManager: BreakOverlayManager? = nil
    ) {
        self.schedulerController = schedulerController
        self.overlayManager = overlayManager ?? BreakOverlayManager()
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
            overlayManager.present(schedulerController: schedulerController)
        case .working:
            overlayManager.dismiss()
        }
    }
}
