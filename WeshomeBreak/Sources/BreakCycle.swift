import Combine
import Foundation
import GrillBreakCore

/// App observation of the running Break Cycle: phase/pause at event rate,
/// remaining at one-second rate. Menu live-title and overlay countdown are
/// adapters; `BreakScheduler` stays the Core state machine.
@MainActor
final class BreakCycle: ObservableObject {
    @Published private(set) var phase: BreakPhase
    @Published private(set) var isPaused: Bool
    /// Per-second remaining. Observing this does not fire `objectWillChange`
    /// on the cycle, so menu-bar SwiftUI content is not rebuilt every tick.
    let remaining: Remaining

    private let scheduler: BreakScheduler
    private let settingsStore: BreakSettingsStore
    private var timer: Timer?

    init(
        scheduler: BreakScheduler? = nil,
        settingsStore: BreakSettingsStore,
        runsTimer: Bool = true
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
        self.remaining = Remaining(seconds: self.scheduler.remaining)
        if runsTimer {
            startTicking()
        }

        settingsStore.onDurationChange = { [weak self] in
            self?.applyScheduleSettings()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Re-derives the scheduler's strategy from the settings store's current
    /// work/rest durations. Takes effect immediately, including on whichever
    /// phase is currently running (see `BreakScheduler.updateStrategy(_:)`).
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

    /// Drives the scheduler one step and republishes. Production Timer and
    /// tests share this seam; tests inject a fake clock and call `tick()`
    /// without starting the Timer.
    func tick() {
        scheduler.tick()
        refreshPublishedState()
    }

    func togglePause() {
        if scheduler.isPaused {
            scheduler.resume()
        } else {
            scheduler.pause()
        }
        refreshPublishedState()
    }

    func skipBreak() {
        guard settingsStore.allowSkip else { return }
        scheduler.skip()
        refreshPublishedState()
    }

    func delayBreak(by interval: TimeInterval? = nil) {
        guard settingsStore.allowDelay else { return }
        scheduler.delay(by: interval ?? settingsStore.delayInterval)
        refreshPublishedState()
    }

    func startBreakNow() {
        scheduler.startBreakNow()
        refreshPublishedState()
    }

    private func refreshPublishedState() {
        let newPhase = scheduler.phase
        let newPaused = scheduler.isPaused
        if phase != newPhase {
            phase = newPhase
        }
        if isPaused != newPaused {
            isPaused = newPaused
        }
        remaining.update(scheduler.remaining)
    }

    var formattedRemaining: String {
        remaining.formatted
    }

    /// Menu-bar status header: phase (or paused) plus remaining `mm:ss`.
    var statusLine: String {
        let phaseLabel: String
        switch phase {
        case .working: phaseLabel = "工作中"
        case .resting: phaseLabel = "休息中"
        }
        let label = isPaused ? "已暂停" : phaseLabel
        return "\(label) · 剩余 \(formattedRemaining)"
    }

    /// Per-second remaining time for surfaces that must tick every second
    /// (overlay countdown, live menu title). Not a peer module.
    @MainActor
    final class Remaining: ObservableObject {
        @Published private(set) var seconds: TimeInterval

        init(seconds: TimeInterval = 0) {
            self.seconds = seconds
        }

        func update(_ value: TimeInterval) {
            if seconds != value {
                seconds = value
            }
        }

        var formatted: String {
            let totalSeconds = max(0, Int(seconds.rounded()))
            let minutes = totalSeconds / 60
            let remainder = totalSeconds % 60
            return String(format: "%02d:%02d", minutes, remainder)
        }
    }
}
