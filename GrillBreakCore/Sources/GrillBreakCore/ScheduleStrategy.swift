import Foundation

/// Determines how long the scheduler should stay in a given phase.
///
/// Conforming types encapsulate a scheduling *model* (e.g. a simple
/// work/rest cycle today; a working-hours-aware model or a Pomodoro-style
/// preset later). `BreakScheduler` depends only on this protocol, so new
/// scheduling models can be added without changing the scheduler.
public protocol ScheduleStrategy: Sendable {
    /// The duration the scheduler should remain in `phase` before moving on.
    func duration(for phase: BreakPhase) -> TimeInterval
}
