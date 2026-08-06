import Foundation

/// Drives the work/rest state machine.
///
/// `BreakScheduler` holds no notion of wall-clock timers itself — it is told
/// "now" (via the injected `clock`, or explicitly through `advance(to:)`)
/// and derives the correct phase from that. This keeps the state machine
/// pure and trivially testable: tests can supply a fake clock and jump
/// forward in time without waiting in real time.
public final class BreakScheduler {
    private var strategy: ScheduleStrategy
    private let clock: () -> Date

    public private(set) var phase: BreakPhase
    private var phaseStartedAt: Date

    /// Whether the scheduler is currently frozen. While paused, `tick()`/
    /// `advance(to:)` are no-ops and `elapsed`/`remaining` stay frozen at the
    /// values they held at the moment of pausing, regardless of how much
    /// real time passes.
    public private(set) var isPaused: Bool = false
    private var pausedAt: Date?

    /// - Parameters:
    ///   - strategy: The scheduling model to consult for phase durations.
    ///   - startingPhase: The phase the scheduler begins in. Defaults to `.working`.
    ///   - clock: Supplies the current time. Defaults to the system clock;
    ///     tests should inject a controllable clock instead.
    public init(
        strategy: ScheduleStrategy,
        startingPhase: BreakPhase = .working,
        clock: @escaping () -> Date = Date.init
    ) {
        self.strategy = strategy
        self.phase = startingPhase
        self.clock = clock
        self.phaseStartedAt = clock()
    }

    /// The configured duration of the current phase, per the strategy.
    public var currentPhaseDuration: TimeInterval {
        strategy.duration(for: phase)
    }

    /// How much time has elapsed since the current phase began, as of `now`.
    /// While paused, this stays frozen at whatever it was when `pause()` was called.
    public var elapsed: TimeInterval {
        let referenceNow = isPaused ? (pausedAt ?? clock()) : clock()
        return referenceNow.timeIntervalSince(phaseStartedAt)
    }

    /// How much time remains in the current phase, floored at zero.
    public var remaining: TimeInterval {
        max(0, currentPhaseDuration - elapsed)
    }

    /// Re-evaluates the state machine against the clock's current time,
    /// advancing through as many phase transitions as have elapsed.
    ///
    /// Safe to call as often as desired (e.g. from a repeating `Timer`) —
    /// it is a no-op if the current phase hasn't finished yet, or if the
    /// scheduler is currently paused.
    public func tick() {
        guard !isPaused else { return }
        advance(to: clock())
    }

    /// Re-evaluates the state machine as of an explicit point in time.
    ///
    /// This is the seam tests use to jump forward without a real clock: a
    /// scheduler backed by a fake `clock` closure can call `advance(to:)`
    /// with any future `Date` and observe the resulting phase. A no-op while
    /// paused — the phase never advances during a pause.
    public func advance(to now: Date) {
        guard !isPaused else { return }
        while now.timeIntervalSince(phaseStartedAt) >= currentPhaseDuration {
            let overflow = now.timeIntervalSince(phaseStartedAt) - currentPhaseDuration
            phase = phase.next
            phaseStartedAt = now.addingTimeInterval(-overflow)
        }
    }

    /// Freezes the current phase's timing. `elapsed`/`remaining` stop
    /// advancing until `resume()` is called. Calling this while already
    /// paused has no effect.
    public func pause() {
        guard !isPaused else { return }
        pausedAt = clock()
        isPaused = true
    }

    /// Unfreezes the current phase's timing from wherever it was left off.
    /// Calling this while not paused has no effect.
    public func resume() {
        guard isPaused, let pausedAt else { return }
        let pauseDuration = clock().timeIntervalSince(pausedAt)
        phaseStartedAt = phaseStartedAt.addingTimeInterval(pauseDuration)
        isPaused = false
        self.pausedAt = nil
    }
}
