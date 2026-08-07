import SwiftUI

/// A pluggable full-screen visual shown behind the countdown during a rest
/// phase. New scene modes conform to this protocol and register with a
/// `BreakSceneModeRegistry`; the overlay window and scheduler never need to
/// change to support additional modes later — they only ever deal with
/// `BreakSceneMode` itself.
public protocol BreakSceneMode: Sendable {
    /// Stable identifier used for persistence (ticket 07's settings) and
    /// fixed-mode selection. Must be unique across registered modes.
    var identifier: String { get }

    /// Human-readable name, e.g. for a future settings picker.
    var displayName: String { get }

    /// Builds this mode's full-screen visual. Called on the main actor,
    /// once per overlay presentation.
    @MainActor func makeView() -> AnyView
}
