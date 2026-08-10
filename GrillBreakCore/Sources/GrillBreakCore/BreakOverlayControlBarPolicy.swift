import Foundation

/// Which buttons belong on the rest-overlay hover control bar for this break.
public struct BreakOverlayControlBarPolicy: Equatable, Sendable {
    public let showsSkip: Bool
    public let showsDelay: Bool
    public let showsStaffMelodyVisibilityToggle: Bool

    public init(allowSkip: Bool, allowDelay: Bool, sceneModeIdentifier: String) {
        showsSkip = allowSkip
        showsDelay = allowDelay
        showsStaffMelodyVisibilityToggle = StaffMelodyVisibility.supports(
            sceneModeIdentifier: sceneModeIdentifier
        )
    }

    public var shouldShowControlBar: Bool {
        showsSkip || showsDelay || showsStaffMelodyVisibilityToggle
    }
}
