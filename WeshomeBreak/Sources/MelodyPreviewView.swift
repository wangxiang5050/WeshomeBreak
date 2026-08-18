import GrillBreakCore
import SwiftUI

/// Melody Preview window: engraves the current Melody Selection exactly as
/// the Staff Melody Scene would, at the currently configured Staff Notation
/// Scale. Both the selected melody and the scale can change live while this
/// window stays open — there is no snapshot to refresh.
struct MelodyPreviewView: View {
    let library: MelodyLibrary
    @ObservedObject var melodyLibraryStore: MelodyLibraryStore
    @ObservedObject var settingsStore: BreakSettingsStore

    var body: some View {
        ZStack {
            StaffMelodyEngravingBackground()
            StaffMelodyPageContent(page: page)
                .padding(32)
        }
        .ignoresSafeArea()
    }

    /// Recomputed whenever `melodyLibraryStore` or `settingsStore` publish a
    /// change, so selecting a different melody or adjusting the scale
    /// updates this preview immediately.
    private var page: StaffMelodyPage {
        StaffMelodyPage.prepare(from: library, settingsStore: settingsStore)
    }
}
