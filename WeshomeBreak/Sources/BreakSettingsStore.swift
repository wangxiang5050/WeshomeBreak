import Foundation
import GrillBreakCore

/// Persists every user-configurable setting from ticket 07's settings panel
/// (work/rest durations, skip/delay permissions + delay length, scene mode
/// selection strategy, Staff Notation Scale, Duration Proportion) to
/// `UserDefaults`, and
/// republishes them as `@Published` properties so the rest of the app
/// updates live the moment a setting changes — no restart required.
///
/// Deliberately plain `UserDefaults` reads/writes (rather than
/// `@AppStorage`) so that a plain `ObservableObject` class — not just a
/// SwiftUI `View` — can hold these properties and have consumers like
/// `BreakCycle` (a `Timer`-driven class, not a view) react to duration
/// changes via `onDurationChange`.
@MainActor
final class BreakSettingsStore: ObservableObject {
    /// The `sceneModeSelectionRaw` value meaning "randomly rotate between
    /// registered modes", as opposed to a specific mode's `identifier`.
    static let randomSelectionValue = "random"

    private enum Keys {
        static let workDuration = "settings.workDuration"
        static let breakDuration = "settings.breakDuration"
        static let allowSkip = "settings.allowSkip"
        static let allowDelay = "settings.allowDelay"
        static let delayInterval = "settings.delayInterval"
        static let sceneModeSelection = "settings.sceneModeSelection"
        static let staffNotationScalePercent = "settings.staffNotationScalePercent"
        static let durationProportionPercent = "settings.durationProportionPercent"
    }

    /// Staff Notation Scale range offered in Settings: covers the
    /// pre-setting hardcoded values (40 and 60) with room either side.
    static let staffNotationScaleRange: ClosedRange<Int> = 40...100

    /// Duration Proportion range: Verovio's 0.05–1.0 as percent, matching
    /// the Stepper's 5-point steps.
    static let durationProportionPercentRange: ClosedRange<Int> = 5...100

    private enum Defaults {
        static let workDuration: TimeInterval = 20 * 60
        static let breakDuration: TimeInterval = 5 * 60
        static let allowSkip = true
        static let allowDelay = true
        static let delayInterval: TimeInterval = 5 * 60
        static let staffNotationScalePercent = 60
        static let durationProportionPercent = 60
    }

    /// Invoked after `workDuration`/`breakDuration` changes.
    /// `BreakCycle` uses this to re-derive the scheduler's
    /// strategy. No other setting needs a reactive hook: skip/delay
    /// permissions and scene mode selection are read directly (via
    /// `@ObservedObject`/property access) at the point they're needed,
    /// rather than pushed to a subscriber.
    var onDurationChange: (() -> Void)?

    @Published var workDuration: TimeInterval {
        didSet {
            persist(workDuration, forKey: Keys.workDuration)
            onDurationChange?()
        }
    }

    @Published var breakDuration: TimeInterval {
        didSet {
            persist(breakDuration, forKey: Keys.breakDuration)
            onDurationChange?()
        }
    }

    @Published var allowSkip: Bool {
        didSet { persist(allowSkip, forKey: Keys.allowSkip) }
    }

    @Published var allowDelay: Bool {
        didSet { persist(allowDelay, forKey: Keys.allowDelay) }
    }

    @Published var delayInterval: TimeInterval {
        didSet { persist(delayInterval, forKey: Keys.delayInterval) }
    }

    /// Either `Self.randomSelectionValue` or a registered scene mode's
    /// `identifier`. Stored as a raw string (rather than
    /// `BreakSceneModeRegistry.SelectionStrategy` directly) so it round-trips
    /// through `UserDefaults` without needing a custom encoding.
    @Published var sceneModeSelectionRaw: String {
        didSet { persist(sceneModeSelectionRaw, forKey: Keys.sceneModeSelection) }
    }

    /// Staff Notation Scale: sizes the notation container (percent) for
    /// both the Staff Melody Scene (read at the start of each break) and
    /// the Melody Preview window (read live).
    @Published var staffNotationScalePercent: Int {
        didSet { persist(staffNotationScalePercent, forKey: Keys.staffNotationScalePercent) }
    }

    /// Duration Proportion: Verovio `spacingNonLinear` as percent (5–100).
    @Published var durationProportionPercent: Int {
        didSet { persist(durationProportionPercent, forKey: Keys.durationProportionPercent) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        workDuration = Self.value(in: defaults, forKey: Keys.workDuration, default: Defaults.workDuration)
        breakDuration = Self.value(in: defaults, forKey: Keys.breakDuration, default: Defaults.breakDuration)
        allowSkip = (defaults.object(forKey: Keys.allowSkip) as? Bool) ?? Defaults.allowSkip
        allowDelay = (defaults.object(forKey: Keys.allowDelay) as? Bool) ?? Defaults.allowDelay
        delayInterval = Self.value(in: defaults, forKey: Keys.delayInterval, default: Defaults.delayInterval)
        sceneModeSelectionRaw = defaults.string(forKey: Keys.sceneModeSelection) ?? Self.randomSelectionValue
        staffNotationScalePercent = (defaults.object(forKey: Keys.staffNotationScalePercent) as? Int)
            ?? Defaults.staffNotationScalePercent
        durationProportionPercent = (defaults.object(forKey: Keys.durationProportionPercent) as? Int)
            ?? Defaults.durationProportionPercent
    }

    private static func value(in defaults: UserDefaults, forKey key: String, default fallback: TimeInterval) -> TimeInterval {
        (defaults.object(forKey: key) as? TimeInterval) ?? fallback
    }

    /// Shared shape behind every setting's `didSet`: writes it through to
    /// `UserDefaults`.
    private func persist(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    /// The scene mode selection strategy derived from `sceneModeSelectionRaw`,
    /// ready to hand to a `BreakSceneModeRegistry`.
    var sceneModeSelectionStrategy: BreakSceneModeRegistry.SelectionStrategy {
        sceneModeSelectionRaw == Self.randomSelectionValue
            ? .randomNoRepeat
            : .fixed(identifier: sceneModeSelectionRaw)
    }
}
