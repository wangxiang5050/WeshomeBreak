import Foundation

/// What the Staff Melody Scene should show for one rest presentation.
public enum StaffMelodyContent: Equatable, Sendable {
    /// Melody Library has no current User Melody — actionable empty state.
    case empty
    /// Accepted MusicXML ready for Verovio engraving in the scene view.
    case score(musicXML: String)
    /// Load failed; message is suitable for a calm on-screen hint.
    case failed(message: String)
}

/// Resolves Melody Library state into the content the Staff Melody Scene shows.
/// Engraving (MusicXML → SVG) happens in the app via Verovio; this type only
/// decides empty / score / failed.
public struct StaffMelodyResolver: Sendable {
    public init() {}

    public func resolve(library: MelodyLibrary) -> StaffMelodyContent {
        guard let melody = library.currentMelody() else {
            return .empty
        }

        do {
            let musicXML = try library.musicXML(for: melody.id)
            if musicXML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failed(message: "无法读取旋律，请在设置中重新导入。")
            }
            return .score(musicXML: musicXML)
        } catch {
            return .failed(message: "无法读取旋律，请在设置中重新导入。")
        }
    }
}
