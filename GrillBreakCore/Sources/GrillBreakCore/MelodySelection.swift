import Foundation

/// Melody Selection strategies. Manual pick keeps the library's current melody.
/// Random draws a User Melody for one rest and does not write that choice back
/// onto the manual selection.
public enum MelodySelectionStrategy: Sendable, Equatable {
    case manual(melodyID: UUID?)
    /// Equal chance among the library, excluding the melody shown on the
    /// previous Staff Melody rest when that still leaves at least one melody.
    case randomNoRepeat
}

public enum MelodySelection {
    /// 「随机旋律」 draws only while Scene Mode Selection is fixed to Staff Melody.
    /// Otherwise the manual current melody. The pin is not written.
    public static func strategy(
        randomMelodyEnabled: Bool,
        sceneModeSelectionRaw: String,
        staffMelodySceneIdentifier: String,
        manualMelodyID: UUID?
    ) -> MelodySelectionStrategy {
        let fixedToStaffMelody = sceneModeSelectionRaw == staffMelodySceneIdentifier
        if randomMelodyEnabled && fixedToStaffMelody {
            return .randomNoRepeat
        }
        return .manual(melodyID: manualMelodyID)
    }
}

/// In-process Melody Selection for Staff Melody rests.
///
/// `lastShownMelodyID` is the melody actually chosen for the most recent
/// Staff Melody rest that had one. An empty rest does not clear it. The held
/// rest survives dismissing the overlay for a delay; it is not persisted.
/// When `defaults` is set, relaunch restores `lastShownMelodyID` from this
/// Mac's UserDefaults. That store is not the shared Melody Library.
public final class MelodySelectionState: @unchecked Sendable {
    /// Existing on-disk key. Stays on this Mac; not part of the iCloud library.
    private static let lastShownKey = "settings.lastShownMelodyID"

    public private(set) var lastShownMelodyID: UUID?

    /// Melody fixed for the rest underway, including while a delay or a
    /// postpone-after-delay is waiting to show it again. `nil` means no rest
    /// is held. `melodyID == nil` means this rest has no melody.
    private var heldRest: HeldMelody?

    private struct HeldMelody: Equatable {
        var melodyID: UUID?
    }

    private let randomIndex: (Int) -> Int
    private let defaults: UserDefaults?

    /// - Parameter randomIndex: Given a pool size, returns the index to pick.
    ///   Must be in `0..<poolSize`. Tests pass a fixed index; production uses
    ///   `Int.random(in:)`.
    /// - Parameter defaults: This Mac's store for `lastShownMelodyID`. When
    ///   set, the stored id is the initial value and later changes are written
    ///   back. `nil` keeps the value in memory only.
    public init(
        lastShownMelodyID: UUID? = nil,
        defaults: UserDefaults? = nil,
        randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }
    ) {
        self.randomIndex = randomIndex
        self.defaults = defaults
        if let defaults, let stored = Self.storedID(in: defaults) {
            self.lastShownMelodyID = stored
        } else {
            self.lastShownMelodyID = lastShownMelodyID
        }
    }

    private static func storedID(in defaults: UserDefaults) -> UUID? {
        guard let raw = defaults.string(forKey: lastShownKey) else { return nil }
        return UUID(uuidString: raw)
    }

    /// Chooses the User Melody for a Staff Melody rest that is about to appear.
    ///
    /// A continuing rest keeps `heldRest` when that melody is still in the
    /// library, including an explicit empty choice. If the held melody was
    /// removed, draws again with random-no-repeat against the current library.
    /// A new rest draws with `strategy` and replaces the hold. A draw that
    /// finds no melody leaves `lastShownMelodyID` unchanged.
    @discardableResult
    public func beginPresentation(
        melodies: [UserMelody],
        using strategy: MelodySelectionStrategy,
        continuingSameRest: Bool
    ) -> UserMelody? {
        if continuingSameRest, let heldRest {
            if let melodyID = heldRest.melodyID,
               let melody = melodies.first(where: { $0.id == melodyID }) {
                return melody
            }
            if heldRest.melodyID == nil {
                return nil
            }
            return draw(melodies: melodies, using: .randomNoRepeat)
        }
        return draw(melodies: melodies, using: strategy)
    }

    private func draw(
        melodies: [UserMelody],
        using strategy: MelodySelectionStrategy
    ) -> UserMelody? {
        let melody: UserMelody?
        switch strategy {
        case .manual(let melodyID):
            melody = melodyID.flatMap { id in melodies.first { $0.id == id } }
        case .randomNoRepeat:
            melody = randomMelody(from: melodies)
        }
        heldRest = HeldMelody(melodyID: melody?.id)
        if let melody, melody.id != lastShownMelodyID {
            lastShownMelodyID = melody.id
            defaults?.set(melody.id.uuidString, forKey: Self.lastShownKey)
        }
        return melody
    }

    private func randomMelody(from melodies: [UserMelody]) -> UserMelody? {
        guard !melodies.isEmpty else { return nil }
        let excludingLast = melodies.filter { $0.id != lastShownMelodyID }
        let pool = excludingLast.isEmpty ? melodies : excludingLast
        return pool[randomIndex(pool.count)]
    }
}
