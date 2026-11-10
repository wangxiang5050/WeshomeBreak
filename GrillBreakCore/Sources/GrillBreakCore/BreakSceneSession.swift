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

/// Staff Melody Scene chrome for one break: session-scoped Visibility,
/// the User Melody chosen for this rest, and its Staff Melody Page.
@MainActor
public final class StaffMelodySceneSession: BreakSceneSession {
    public static let sceneModeIdentifier = "staff-melody"

    /// User Melody chosen for this presentation. `nil` is the empty state.
    /// Updated if that melody leaves the library during the rest.
    @Published public private(set) var melodyID: UUID?

    /// Staff Melody Page for `melodyID` at the scale captured when this rest began.
    @Published public private(set) var page: StaffMelodyPage = .empty

    @Published private var visibility = StaffMelodyVisibility()

    private var selection: MelodySelectionState?
    private var scalePercent = 60
    private var durationProportionPercent = 60

    public init(melodyID: UUID? = nil) {
        self.melodyID = melodyID
        super.init()
    }

    /// Chooses the User Melody for this rest and engraves its Staff Melody Page.
    /// Scale and Duration Proportion stay fixed for this presentation.
    public func beginRest(
        in library: MelodyLibrary,
        using strategy: MelodySelectionStrategy,
        continuingSameRest: Bool,
        selection: MelodySelectionState,
        scalePercent: Int,
        durationProportionPercent: Int
    ) {
        self.selection = selection
        self.scalePercent = scalePercent
        self.durationProportionPercent = durationProportionPercent
        let melody = selection.beginPresentation(
            melodies: library.melodies(),
            using: strategy,
            continuingSameRest: continuingSameRest
        )
        show(melody, in: library)
    }

    /// Melody Library membership or a score file changed during this rest.
    /// Keeps the held melody when it is still a member and engraves again.
    /// If that melody left, draws a replacement with the held-rest rule.
    public func libraryChanged(in library: MelodyLibrary) {
        guard let selection else { return }
        let melody = selection.beginPresentation(
            melodies: library.melodies(),
            using: .randomNoRepeat,
            continuingSameRest: true
        )
        show(melody, in: library)
    }

    private func show(_ melody: UserMelody?, in library: MelodyLibrary) {
        melodyID = melody?.id
        page = StaffMelodyPage.prepare(
            from: library,
            melodyID: melody?.id,
            scalePercent: scalePercent,
            durationProportionPercent: durationProportionPercent
        )
    }

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
