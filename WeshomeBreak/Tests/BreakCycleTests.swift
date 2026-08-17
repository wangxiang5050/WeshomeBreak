import Combine
import Foundation
import GrillBreakCore
import Testing
@testable import WeshomeBreak

@Suite("BreakCycle")
@MainActor
struct BreakCycleTests {

    final class FakeClock {
        var now: Date

        init(_ now: Date = Date(timeIntervalSince1970: 0)) {
            self.now = now
        }

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    private func makeCycle(
        workDuration: TimeInterval = 20,
        breakDuration: TimeInterval = 5,
        startingPhase: BreakPhase = .working
    ) -> (BreakCycle, FakeClock) {
        let clock = FakeClock()
        let scheduler = BreakScheduler(
            strategy: SimpleCycleSchedule(
                workDuration: workDuration,
                breakDuration: breakDuration
            ),
            startingPhase: startingPhase,
            clock: { clock.now }
        )
        let suite = "break-cycle-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = BreakSettingsStore(defaults: defaults)
        let cycle = BreakCycle(
            scheduler: scheduler,
            settingsStore: settings,
            runsTimer: false
        )
        return (cycle, clock)
    }

    @Test("remaining tick does not republish phase")
    func remainingTickDoesNotRepublishPhase() {
        let (cycle, clock) = makeCycle(workDuration: 20)
        var phaseValues: [BreakPhase] = []
        let cancellable = cycle.$phase.sink { phaseValues.append($0) }

        clock.advance(by: 1)
        cycle.tick()

        #expect(phaseValues == [.working])
        #expect(cycle.remaining.seconds == 19)
        _ = cancellable
    }

    @Test("remaining tick does not fire cycle objectWillChange")
    func remainingTickDoesNotFireCycleObjectWillChange() {
        let (cycle, clock) = makeCycle(workDuration: 20)
        var willChangeCount = 0
        let cancellable = cycle.objectWillChange.sink { willChangeCount += 1 }

        clock.advance(by: 1)
        cycle.tick()

        #expect(willChangeCount == 0)
        #expect(cycle.remaining.seconds == 19)
        _ = cancellable
    }

    @Test("remaining tick does not republish pause")
    func remainingTickDoesNotRepublishPause() {
        let (cycle, clock) = makeCycle(workDuration: 20)
        var pauseValues: [Bool] = []
        let cancellable = cycle.$isPaused.sink { pauseValues.append($0) }

        clock.advance(by: 1)
        cycle.tick()

        #expect(pauseValues == [false])
        _ = cancellable
    }

    @Test("phase publishes when the work duration elapses")
    func phasePublishesOnTransition() {
        let (cycle, clock) = makeCycle(workDuration: 20, breakDuration: 5)
        var phases: [BreakPhase] = []
        let cancellable = cycle.$phase.sink { phases.append($0) }

        clock.advance(by: 20)
        cycle.tick()

        #expect(phases == [.working, .resting])
        #expect(cycle.phase == .resting)
        _ = cancellable
    }

    @Test("status line while working")
    func statusLineWorking() {
        let (cycle, _) = makeCycle(workDuration: 20 * 60)
        #expect(cycle.statusLine == "工作中 · 剩余 20:00")
    }

    @Test("status line while resting")
    func statusLineResting() {
        let (cycle, clock) = makeCycle(workDuration: 20, breakDuration: 5 * 60)
        clock.advance(by: 20)
        cycle.tick()
        #expect(cycle.statusLine == "休息中 · 剩余 05:00")
    }

    @Test("status line while paused")
    func statusLinePaused() {
        let (cycle, _) = makeCycle(workDuration: 20 * 60)
        cycle.togglePause()
        #expect(cycle.statusLine == "已暂停 · 剩余 20:00")
        #expect(cycle.isPaused)
    }
}
