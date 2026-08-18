import Foundation

/// Staff Melody Page: Melody Library + Melody Selection → empty / failed /
/// ready HTML for the Verovio Score Rendering adapter.
public enum StaffMelodyPage: Equatable, Sendable {
    /// Melody Library has no current User Melody — actionable empty state.
    case empty
    /// Load failed; message is suitable for a calm on-screen hint.
    case failed(message: String)
    /// Offline HTML page ready for the Verovio WKWebView adapter.
    case ready(html: String)

    private static let readFailureMessage = "无法读取旋律，请在设置中重新导入。"

    /// Builds the Staff Melody Page for the library's current Melody
    /// Selection, engraved at the given Staff Notation Scale and note-spacing
    /// percents (Spacing Coefficient / Duration Proportion).
    public static func prepare(
        from library: MelodyLibrary,
        scalePercent: Int,
        spacingCoefficientPercent: Int,
        durationProportionPercent: Int
    ) -> StaffMelodyPage {
        guard let melody = library.currentMelody() else {
            return .empty
        }

        do {
            let musicXML = try library.musicXML(for: melody.id)
            if musicXML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failed(message: Self.readFailureMessage)
            }
            return .ready(
                html: StaffMelodyEngravingPage.html(
                    musicXML: musicXML,
                    scalePercent: scalePercent,
                    spacingCoefficientPercent: spacingCoefficientPercent,
                    durationProportionPercent: durationProportionPercent
                )
            )
        } catch {
            return .failed(message: Self.readFailureMessage)
        }
    }
}
