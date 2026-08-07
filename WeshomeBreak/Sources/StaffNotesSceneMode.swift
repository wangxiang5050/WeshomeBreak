import GrillBreakCore
import SwiftUI

/// The one `BreakSceneMode` registered today: the five-line-staff /
/// flying-notes visual. Lives in the app target (rather than
/// `GrillBreakCore`) because its view, `StaffNotesView`, is a SwiftUI/AppKit
/// concern — `GrillBreakCore` only defines the pluggable `BreakSceneMode`
/// protocol and the mode-selection logic around it.
struct StaffNotesSceneMode: BreakSceneMode {
    let identifier = "staff-notes"
    let displayName = "五线谱音符"

    @MainActor
    func makeView() -> AnyView {
        AnyView(StaffNotesView())
    }
}
