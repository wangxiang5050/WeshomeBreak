import SwiftUI

/// Carries session-scoped Staff Melody Visibility into the Staff Melody Scene view.
private struct StaffMelodyContentVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var staffMelodyContentVisible: Bool {
        get { self[StaffMelodyContentVisibleKey.self] }
        set { self[StaffMelodyContentVisibleKey.self] = newValue }
    }
}
