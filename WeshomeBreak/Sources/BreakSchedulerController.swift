import Foundation
import GrillBreakCore

/// Owns the `GrillBreakCore.BreakScheduler` for the running app and bridges
/// it into SwiftUI: drives it with a repeating `Timer` and republishes its
/// state as `@Published` properties so views update automatically.
///
/// The scheduler itself has no notion of timers or observation — this class
/// is the (thin, UI-layer, untested-by-design per the spec) glue that wires
/// it into a running app.
@MainActor
final class BreakSchedulerController: ObservableObject {
    @Published private(set) var phase: BreakPhase
    @Published private(set) var isPaused: Bool
    @Published private(set) var remaining: TimeInterval

    private let scheduler: BreakScheduler
    private var timer: Timer?

    init(
        scheduler: BreakScheduler = BreakScheduler(
            strategy: SimpleCycleSchedule(workDuration: 20 * 60, breakDuration: 5 * 60)
        )
    ) {
        self.scheduler = scheduler
        self.phase = scheduler.phase
        self.isPaused = scheduler.isPaused
        self.remaining = scheduler.remaining
        startTicking()
    }

    deinit {
        timer?.invalidate()
    }

    private func startTicking() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        scheduler.tick()
        refreshPublishedState()
    }

    /// Toggles between paused and running, matching the menu bar's single
    /// "暂停/继续" entry whose label flips based on `isPaused`.
    func togglePause() {
        if scheduler.isPaused {
            scheduler.resume()
        } else {
            scheduler.pause()
        }
        refreshPublishedState()
    }

    /// The default "延迟" duration per the spec: pushes the current rest
    /// back by 5 minutes. Callers may pass a different interval; this is
    /// just what the overlay's "延迟" button uses.
    static let defaultDelayInterval: TimeInterval = 5 * 60

    /// Ends the current rest immediately; the next rest only triggers after
    /// a full work duration. A no-op unless currently resting.
    func skipBreak() {
        scheduler.skip()
        refreshPublishedState()
    }

    /// Ends the current rest immediately, re-triggering the same rest after
    /// `interval` (defaulting to `defaultDelayInterval`). Callable
    /// repeatedly with no limit. A no-op unless currently resting.
    func delayBreak(by interval: TimeInterval = defaultDelayInterval) {
        scheduler.delay(by: interval)
        refreshPublishedState()
    }

    private func refreshPublishedState() {
        phase = scheduler.phase
        isPaused = scheduler.isPaused
        remaining = scheduler.remaining
    }

    /// `remaining` formatted as `mm:ss`, shared by the menu bar status line
    /// and the break overlay's countdown display.
    var formattedRemaining: String {
        let totalSeconds = max(0, Int(remaining.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
