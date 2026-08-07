import Foundation

/// Reports whether the user is currently in a state that should postpone an
/// automatically-triggered break — e.g. presenting a full-screen app
/// (slideshow, video, meeting) or with the system's Do Not Disturb/Focus
/// mode enabled. `BreakScheduler` depends only on this protocol, never on a
/// concrete system API, so tests can simulate either condition without
/// touching real system state.
public protocol BreakInterruptionSource: Sendable {
    /// `true` while some app is occupying the screen full-screen.
    func isFullScreenAppActive() -> Bool

    /// `true` while the system is in Do Not Disturb / Focus mode.
    func isDoNotDisturbActive() -> Bool
}

extension BreakInterruptionSource {
    /// `true` if either condition currently applies.
    public func isInterrupting() -> Bool {
        isFullScreenAppActive() || isDoNotDisturbActive()
    }
}

/// The default source used when nothing is injected: never postpones a
/// break. Concrete apps inject a real, system-backed implementation instead.
public struct NoInterruptionSource: BreakInterruptionSource {
    public init() {}
    public func isFullScreenAppActive() -> Bool { false }
    public func isDoNotDisturbActive() -> Bool { false }
}
