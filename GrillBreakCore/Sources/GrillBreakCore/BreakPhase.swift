import Foundation

/// The two phases a `BreakScheduler` alternates between.
public enum BreakPhase: Equatable, Sendable {
    case working
    case resting

    /// The phase that follows this one in a simple work/rest cycle.
    public var next: BreakPhase {
        switch self {
        case .working: return .resting
        case .resting: return .working
        }
    }
}
