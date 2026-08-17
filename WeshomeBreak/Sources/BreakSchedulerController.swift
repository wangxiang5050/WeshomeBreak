import Foundation
import GrillBreakCore

/// Owns the `GrillBreakCore.BreakScheduler` for the running app and bridges
/// it into SwiftUI: drives it with a repeating `Timer` and republishes
/// phase/pause as `@Published` properties. Per-second remaining time lives on
/// `countdown` so menu-bar SwiftUI content is not rebuilt every tick.
@MainActor
final class BreakSchedulerController: ObservableObject {
    @Published private(set) var phase: BreakPhase
    @Published private(set) var isPaused: Bool
    /// Per-second remaining time. Observed by the overlay via `countdown`,
    /// not via this object's `objectWillChange` (see `BreakCountdown`).
    let countdown: BreakCountdown

    private let scheduler: BreakScheduler
    private let settingsStore: BreakSettingsStore
    private var timer: Timer?

    init(
        scheduler: BreakScheduler? = nil,
        settingsStore: BreakSettingsStore
    ) {
        self.settingsStore = settingsStore
        self.scheduler = scheduler ?? BreakScheduler(
            strategy: SimpleCycleSchedule(
                workDuration: settingsStore.workDuration,
                breakDuration: settingsStore.breakDuration
            ),
            interruptionSource: SystemBreakInterruptionSource()
        )
        self.phase = self.scheduler.phase
        self.isPaused = self.scheduler.isPaused
        self.countdown = BreakCountdown(remaining: self.scheduler.remaining)
        startTicking()

        settingsStore.onDurationChange = { [weak self] in
            self?.applyScheduleSettings()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Re-derives the scheduler's strategy from the settings store's current
    /// work/rest durations. Called once up front isn't necessary — the
    /// scheduler is already constructed with those values — this only fires
    /// on subsequent changes, via `settingsStore.onChange`. Takes effect
    /// immediately, including on whichever phase is currently running (see
    /// `BreakScheduler.updateStrategy(_:)`).
    private func applyScheduleSettings() {
        scheduler.updateStrategy(
            SimpleCycleSchedule(
                workDuration: settingsStore.workDuration,
                breakDuration: settingsStore.breakDuration
            )
        )
        refreshPublishedState()
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

    /// Ends the current rest immediately; the next rest only triggers after
    /// a full work duration. A no-op unless currently resting, or skipping
    /// is disallowed in settings.
    func skipBreak() {
        guard settingsStore.allowSkip else { return }
        scheduler.skip()
        refreshPublishedState()
    }

    /// Ends the current rest immediately, re-triggering the same rest after
    /// `interval` (defaulting to the settings panel's configured delay
    /// length). Callable repeatedly with no limit. A no-op unless currently
    /// resting, or delaying is disallowed in settings.
    func delayBreak(by interval: TimeInterval? = nil) {
        guard settingsStore.allowDelay else { return }
        scheduler.delay(by: interval ?? settingsStore.delayInterval)
        refreshPublishedState()
    }

    /// Manually starts a rest right now, without waiting for the work timer
    /// to finish. Drives the exact same `phase` transition an automatic
    /// trigger would, so Rest Overlay's phase observation presents the
    /// covering via the identical path. A no-op unless currently working.
    func startBreakNow() {
        scheduler.startBreakNow()
        refreshPublishedState()
    }

    private func refreshPublishedState() {
        let newPhase = scheduler.phase
        let newPaused = scheduler.isPaused
        // Only publish when menu-relevant fields change. Assigning every tick
        // (even with equal values) would still fire `objectWillChange` and
        // rebuild an open MenuBarExtra `.menu`.
        if phase != newPhase {
            phase = newPhase
        }
        if isPaused != newPaused {
            isPaused = newPaused
        }
        countdown.update(scheduler.remaining)
    }

    /// `remaining` formatted as `mm:ss` for the menu-bar status line.
    var formattedRemaining: String {
        countdown.formattedRemaining
    }

    /// Menu-bar status header: phase (or paused) plus remaining `mm:ss`.
    var menuStatusLine: String {
        let phaseLabel: String
        switch phase {
        case .working: phaseLabel = "工作中"
        case .resting: phaseLabel = "休息中"
        }
        let label = isPaused ? "已暂停" : phaseLabel
        return "\(label) · 剩余 \(formattedRemaining)"
    }
}
