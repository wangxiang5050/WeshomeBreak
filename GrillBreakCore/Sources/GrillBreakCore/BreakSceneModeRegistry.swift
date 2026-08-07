import Foundation

/// Holds the set of registered `BreakSceneMode`s and decides which one to
/// use for a given rest, according to a `SelectionStrategy`.
///
/// This is deliberately pure decision logic with no SwiftUI/AppKit
/// involvement — like `BreakScheduler`'s fake-clock design, tests inject a
/// deterministic `randomIndex` closure instead of relying on real
/// randomness, so selection order is fully predictable in tests.
public struct BreakSceneModeRegistry {
    /// How a mode should be picked for the next rest.
    public enum SelectionStrategy: Sendable, Equatable {
        /// Always use the mode with this identifier (falls back to `nil`
        /// if no registered mode matches — callers decide how to handle
        /// that, e.g. by falling back to a default mode).
        case fixed(identifier: String)
        /// Pick at random, but never the same mode that was selected last
        /// time (unless only one mode is registered, in which case the
        /// constraint is impossible to satisfy and is waived).
        case randomNoRepeat
    }

    private let modes: [BreakSceneMode]
    private var lastSelectedIdentifier: String?
    private let randomIndex: (Int) -> Int

    /// - Parameters:
    ///   - modes: The modes available for selection, in registration order.
    ///   - randomIndex: Given a pool size, returns the index to pick from
    ///     that pool. Defaults to `Int.random(in:)`; tests supply a
    ///     deterministic closure instead.
    public init(
        modes: [BreakSceneMode],
        randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }
    ) {
        self.modes = modes
        self.randomIndex = randomIndex
    }

    /// The modes this registry was constructed with, in registration order.
    public var registeredModes: [BreakSceneMode] { modes }

    /// Selects a mode according to `strategy`. Returns `nil` only if no
    /// mode satisfies the strategy (e.g. `.fixed` with an unknown
    /// identifier, or no modes registered at all).
    public mutating func selectMode(using strategy: SelectionStrategy) -> BreakSceneMode? {
        switch strategy {
        case .fixed(let identifier):
            return modes.first { $0.identifier == identifier }
        case .randomNoRepeat:
            return selectRandomNoRepeat()
        }
    }

    private mutating func selectRandomNoRepeat() -> BreakSceneMode? {
        guard !modes.isEmpty else { return nil }
        let pool = modes.count > 1
            ? modes.filter { $0.identifier != lastSelectedIdentifier }
            : modes
        guard !pool.isEmpty else { return nil }

        let chosen = pool[randomIndex(pool.count)]
        lastSelectedIdentifier = chosen.identifier
        return chosen
    }
}
