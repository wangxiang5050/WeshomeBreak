import Foundation
import SwiftUI
import Testing
@testable import GrillBreakCore

@Suite("BreakSceneModeRegistry")
struct BreakSceneModeRegistryTests {

    private struct StubMode: BreakSceneMode {
        let identifier: String
        let displayName: String

        @MainActor
        func makeView() -> AnyView { AnyView(EmptyView()) }
    }

    /// Builds a registry whose "randomness" is fully deterministic: it
    /// always picks the element at `fixedIndex` (clamped into range),
    /// matching how `BreakSchedulerTests`'s `FakeClock` avoids real time.
    private func makeRegistry(
        modeCount: Int,
        fixedIndex: Int = 0
    ) -> (BreakSceneModeRegistry, modes: [StubMode]) {
        let modes = (0..<modeCount).map { StubMode(identifier: "mode-\($0)", displayName: "Mode \($0)") }
        let registry = BreakSceneModeRegistry(modes: modes) { poolSize in
            min(fixedIndex, max(0, poolSize - 1))
        }
        return (registry, modes)
    }

    @Test("fixed strategy returns the mode with the matching identifier")
    func fixedStrategyReturnsMatchingMode() {
        var (registry, modes) = makeRegistry(modeCount: 3)
        let selected = registry.selectMode(using: .fixed(identifier: modes[1].identifier))
        #expect(selected?.identifier == modes[1].identifier)
    }

    @Test("fixed strategy returns nil when no mode matches the identifier")
    func fixedStrategyReturnsNilForUnknownIdentifier() {
        var (registry, _) = makeRegistry(modeCount: 3)
        let selected = registry.selectMode(using: .fixed(identifier: "does-not-exist"))
        #expect(selected == nil)
    }

    @Test("random-no-repeat never selects the same mode twice in a row across many draws")
    func randomNoRepeatNeverRepeatsAcrossManyDraws() {
        let modes = (0..<4).map { StubMode(identifier: "mode-\($0)", displayName: "Mode \($0)") }
        // A simple deterministic sequence that would repeat the same
        // underlying pool index every time if the "exclude last selection"
        // filtering weren't applied.
        var registry = BreakSceneModeRegistry(modes: modes) { _ in 0 }

        var previousIdentifier: String?
        for _ in 0..<20 {
            let selected = registry.selectMode(using: .randomNoRepeat)
            #expect(selected != nil)
            if let previousIdentifier {
                #expect(selected?.identifier != previousIdentifier)
            }
            previousIdentifier = selected?.identifier
        }
    }

    @Test("random-no-repeat with a single registered mode keeps returning that mode")
    func randomNoRepeatWithSingleModeWaivesTheConstraint() {
        var (registry, modes) = makeRegistry(modeCount: 1)
        let first = registry.selectMode(using: .randomNoRepeat)
        let second = registry.selectMode(using: .randomNoRepeat)
        #expect(first?.identifier == modes[0].identifier)
        #expect(second?.identifier == modes[0].identifier)
    }

    @Test("random-no-repeat returns nil when no modes are registered")
    func randomNoRepeatReturnsNilWhenEmpty() {
        var registry = BreakSceneModeRegistry(modes: [])
        #expect(registry.selectMode(using: .randomNoRepeat) == nil)
    }

    @Test("registeredModes preserves registration order")
    func registeredModesPreservesOrder() {
        let (registry, modes) = makeRegistry(modeCount: 3)
        #expect(registry.registeredModes.map(\.identifier) == modes.map(\.identifier))
    }
}
