import Combine
import Foundation
import GrillBreakCore

/// Window adapter behind Rest Overlay: production uses AppKit `NSWindow`s;
/// tests record present/dismiss without opening a real covering.
@MainActor
protocol RestOverlayWindows: AnyObject {
    var isPresenting: Bool { get }
    func present(sceneMode: BreakSceneMode)
    func dismiss()
}

/// Rest Overlay: Break Cycle phase → show the selected Break Scene Mode, or
/// dismiss. AppKit windows sit behind `RestOverlayWindows`.
@MainActor
final class RestOverlay {
    private let settingsStore: BreakSettingsStore
    private var sceneModeRegistry: BreakSceneModeRegistry
    private let windows: RestOverlayWindows
    private var cancellable: AnyCancellable?

    init(
        settingsStore: BreakSettingsStore,
        sceneModeRegistry: BreakSceneModeRegistry,
        windows: RestOverlayWindows
    ) {
        self.settingsStore = settingsStore
        self.sceneModeRegistry = sceneModeRegistry
        self.windows = windows
    }

    /// Observes Break Cycle phase (event rate) and keeps the covering in sync.
    func start(observing breakCycle: BreakCycle) {
        sync(phase: breakCycle.phase)
        cancellable = breakCycle.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                self?.sync(phase: phase)
            }
    }

    /// `resting` presents the mode from the current Scene Mode Selection;
    /// `working` dismisses. A second `resting` while already presenting is a
    /// no-op (does not re-select or re-present).
    func sync(phase: BreakPhase) {
        switch phase {
        case .resting:
            guard !windows.isPresenting else { return }
            let mode = sceneModeRegistry.selectMode(using: settingsStore.sceneModeSelectionStrategy)
                ?? sceneModeRegistry.registeredModes.first
            guard let mode else { return }
            windows.present(sceneMode: mode)
        case .working:
            windows.dismiss()
        }
    }
}
