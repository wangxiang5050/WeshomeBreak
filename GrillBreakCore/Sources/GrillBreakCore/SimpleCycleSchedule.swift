import Foundation

/// The default scheduling model: a fixed work duration followed by a fixed
/// rest duration, repeating indefinitely. Does not consider time-of-day or
/// any other context — see `ScheduleStrategy` for how alternative models can
/// be plugged in later.
public struct SimpleCycleSchedule: ScheduleStrategy {
    public var workDuration: TimeInterval
    public var breakDuration: TimeInterval

    public init(workDuration: TimeInterval, breakDuration: TimeInterval) {
        self.workDuration = workDuration
        self.breakDuration = breakDuration
    }

    public func duration(for phase: BreakPhase) -> TimeInterval {
        switch phase {
        case .working: return workDuration
        case .resting: return breakDuration
        }
    }
}
