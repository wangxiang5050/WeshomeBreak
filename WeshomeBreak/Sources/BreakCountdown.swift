import Foundation

/// Live remaining-time publisher for surfaces that must tick every second
/// (the break overlay). Kept separate from `BreakSchedulerController`'s
/// `ObservableObject` so menu-bar SwiftUI content is not rebuilt on each
/// tick — rebuilding an open `.menu` MenuBarExtra desyncs NSMenu hover
/// highlight from hit-testing.
@MainActor
final class BreakCountdown: ObservableObject {
    @Published private(set) var remaining: TimeInterval

    init(remaining: TimeInterval = 0) {
        self.remaining = remaining
    }

    func update(_ value: TimeInterval) {
        if remaining != value {
            remaining = value
        }
    }

    var formattedRemaining: String {
        let totalSeconds = max(0, Int(remaining.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
