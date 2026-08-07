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

    /// Overrides `strategy.duration(for:)` for the *current* phase only.
    /// Used by `delay(by:)` to make the working phase that stands in for a
    /// "snoozed rest" last exactly the delay interval, rather than a full
    /// work duration. Cleared automatically the next time the phase
    /// transitions (in `advance(to:)`), so it never leaks into a
    /// subsequent, unrelated phase.
    private var phaseDurationOverride: TimeInterval?

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

    /// The configured duration of the current phase: `phaseDurationOverride`
    /// if one is set (see `delay(by:)`), otherwise the strategy's normal
    /// duration for this phase.
    public var currentPhaseDuration: TimeInterval {
        phaseDurationOverride ?? strategy.duration(for: phase)
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
            phaseDurationOverride = nil
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

    /// Ends the current rest immediately and starts a fresh, full-length
    /// working phase right now. The *next* rest will only trigger after a
    /// complete work duration has elapsed — skipping never shortens a
    /// future phase. A no-op unless `phase == .resting`.
    public func skip() {
        guard phase == .resting else { return }
        phase = .working
        phaseStartedAt = clock()
        phaseDurationOverride = nil
    }

    /// Ends the current rest immediately, but re-triggers the *same* rest
    /// (a full break duration, not a shortened one) after `interval` has
    /// elapsed. Implemented as a working phase whose duration is
    /// temporarily overridden to `interval` — once that elapses,
    /// `advance(to:)`'s normal phase transition clears the override and
    /// resumes the regular working→resting cycle with a full break.
    ///
    /// Callable repeatedly with no limit: each call while `phase == .resting`
    /// pushes the rest back by another `interval`. A no-op unless
    /// `phase == .resting`.
    public func delay(by interval: TimeInterval) {
        guard phase == .resting else { return }
        phase = .working
        phaseStartedAt = clock()
        phaseDurationOverride = interval
    }

    /// Ends the current work period immediately and starts a fresh,
    /// full-length rest right now — the same rest an automatic trigger
    /// would start once the work duration elapsed on its own. The work
    /// period that follows this rest still runs for a complete,
    /// unshortened duration, so manually starting a rest early never
    /// disturbs the schedule beyond this one rest. A no-op unless
    /// `phase == .working`, and while paused — pausing freezes the overall
    /// schedule, so a manual trigger must not force a phase change until
    /// `resume()` is called.
    public func startBreakNow() {
        guard phase == .working, !isPaused else { return }
        phase = .resting
        phaseStartedAt = clock()
        phaseDurationOverride = nil
    }
}
