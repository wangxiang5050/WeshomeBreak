import Combine
import Foundation

/// Session chrome for one Rest Overlay presentation of a Break Scene Mode.
/// Rest Overlay renders `hoverBarExtraTitle` without interpreting it.
/// Scenes with no extra chrome use this inert base (the second adapter).
@MainActor
public class BreakSceneSession: ObservableObject {
    /// Extra hover-bar button owned by this scene. `nil` means none.
    public var hoverBarExtraTitle: String? { nil }

    /// Whether this scene's content area is shown. Overlay does not read this;
    /// the scene view does.
    public var showsContent: Bool { true }

    public init() {}

    public func performHoverBarExtra() {}
}

/// Staff Melody Scene chrome for one break: session-scoped Visibility.
@MainActor
public final class StaffMelodySceneSession: BreakSceneSession {
    public static let sceneModeIdentifier = "staff-melody"

    @Published private var visibility = StaffMelodyVisibility()

    public override var hoverBarExtraTitle: String? { visibility.toggleTitle }
    public override var showsContent: Bool { visibility.isContentVisible }

    public override func performHoverBarExtra() {
        objectWillChange.send()
        visibility.toggle()
    }
}

/// Session-scoped visibility of Staff Melody Scene content during one break.
/// Hiding clears the engraved score / empty / failure copy only.
struct StaffMelodyVisibility: Equatable, Sendable {
    var isContentVisible: Bool

    init(isContentVisible: Bool = true) {
        self.isContentVisible = isContentVisible
    }

    mutating func toggle() {
        isContentVisible.toggle()
    }

    var toggleTitle: String {
        isContentVisible ? "隐藏旋律" : "显示旋律"
    }
}
