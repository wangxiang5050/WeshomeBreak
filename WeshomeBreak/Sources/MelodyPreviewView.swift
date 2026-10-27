import GrillBreakCore
import SwiftUI

/// Melody Preview window: engraves the manual current melody at the current
/// Staff Notation Scale and Duration Proportion. It does not follow a random
/// rest draw. The pin and those settings update this window live.
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
    /// change, so selecting a different melody or adjusting scale / spacing
    /// updates this preview immediately.
    private var page: StaffMelodyPage {
        StaffMelodyPage.prepare(from: library, settingsStore: settingsStore)
    }
}
