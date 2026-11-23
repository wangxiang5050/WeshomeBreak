import Combine
import Foundation

/// Session chrome for one Rest Overlay presentation of a Break Scene Mode.
/// Rest Overlay renders `hoverBarExtraTitle` without interpreting it.
/// Scenes with no extra chrome use this inert base (the second adapter).
@MainActor
public class BreakSceneSession: ObservableObject {
    /// Extra hover-bar button owned by this scene. `nil` means none.
    public var hoverBarExtraTitle: String? { nil }

    /// Icon button owned by this scene. `nil` means none.
    public var hoverBarSymbolName: String? { nil }

    /// Whether this scene's content area is shown. Overlay does not read this;
    /// the scene view does.
    public var showsContent: Bool { true }

    public init() {}

    public func performHoverBarExtra() {}

    public func performHoverBarSymbol() {}

    public func tickPlayback(seconds: TimeInterval) {}

    public func dismissPlayback() {}

    public func notePlaybackOutput(_ output: PlaybackOutput) {}

    fileprivate func publishPlayback(_ moment: MelodyPlaybackMoment) {
        playbackSound = moment
    }

    /// Latest notes the scene wants sounded. Empty until a scene publishes some.
    @Published public private(set) var playbackSound = MelodyPlaybackMoment(
        phase: .idle,
        offersStart: false,
        attacks: [],
        silenced: false,
        line: nil
    )
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

    /// Same moment the overlay sounds. Tests read this name.
    public var playbackMoment: MelodyPlaybackMoment { playbackSound }

    private var loadedMusicXML: String?
    private var selection: MelodySelectionState?
    private var scalePercent = 60
    private var durationProportionPercent = 60
    private var tempo = PlaybackTempo.defaultTempo
    private var playback = MelodyPlayback(musicXML: nil, tempo: .defaultTempo)

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
        durationProportionPercent: Int,
        tempo: PlaybackTempo = .defaultTempo
    ) {
        self.selection = selection
        self.scalePercent = scalePercent
        self.durationProportionPercent = durationProportionPercent
        self.tempo = tempo
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
        if melody?.id == melodyID, case .ready = page {
            let xml = melodyID.flatMap { try? library.musicXML(for: $0) }
            if xml == loadedMusicXML { return }
        }
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
        let musicXML: String?
        if case .ready = page, let melodyID {
            musicXML = try? library.musicXML(for: melodyID)
        } else {
            musicXML = nil
        }
        if playback.tempo != tempo {
            playback = MelodyPlayback(musicXML: nil, tempo: tempo)
        }
        loadedMusicXML = musicXML
        publishPlayback(playback.replace(musicXML: musicXML))
    }

    /// Line for the engraved staff. Hidden with the melody, including while sound continues.
    public var playbackLine: PlaybackLine? {
        guard showsContent else { return nil }
        return playbackMoment.line
    }

    public override var hoverBarExtraTitle: String? { visibility.toggleTitle }
    public override var showsContent: Bool { visibility.isContentVisible }

    public override var hoverBarSymbolName: String? {
        guard playback.isAvailable, case .ready = page else { return nil }
        return playbackMoment.offersStart ? "play.fill" : "pause.fill"
    }

    public override func performHoverBarExtra() {
        objectWillChange.send()
        visibility.toggle()
    }

    public override func performHoverBarSymbol() {
        publishPlayback(playbackMoment.offersStart ? playback.start() : playback.pause())
    }

    public override func tickPlayback(seconds: TimeInterval) {
        let next = playback.advance(seconds: seconds)
        if next != playbackSound {
            publishPlayback(next)
        }
    }

    public override func dismissPlayback() {
        publishPlayback(playback.dismiss())
    }

    public override func notePlaybackOutput(_ output: PlaybackOutput) {
        let next = playback.noteOutput(output)
        if next != playbackSound {
            publishPlayback(next)
        }
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
