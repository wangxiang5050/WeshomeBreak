import Foundation

/// Session-scoped visibility of Staff Melody Scene content during one break.
/// Hiding clears the engraved score / empty / failure copy only; the break,
/// countdown, and Break Scene Mode selection are unchanged. Each new break
/// starts visible again.
public struct StaffMelodyVisibility: Equatable, Sendable {
    public static let sceneModeIdentifier = "staff-melody"

    public var isContentVisible: Bool

    public init(isContentVisible: Bool = true) {
        self.isContentVisible = isContentVisible
    }

    public mutating func toggle() {
        isContentVisible.toggle()
    }

    /// Control-bar label for the action that flips the current state.
    public var toggleTitle: String {
        isContentVisible ? "隐藏旋律" : "显示旋律"
    }

    public static func supports(sceneModeIdentifier: String) -> Bool {
        sceneModeIdentifier == Self.sceneModeIdentifier
    }
}
