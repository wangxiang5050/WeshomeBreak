import Foundation
import Testing
@testable import GrillBreakCore

@Suite("BreakScheduler with an interruption source")
struct BreakInterruptionSourceTests {

    /// A controllable clock that tests can move forward without waiting in
    /// real time.
    final class FakeClock {
        var now: Date

        init(_ now: Date = Date(timeIntervalSince1970: 0)) {
            self.now = now
        }

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    /// A stub the tests flip on and off directly, instead of touching any
    /// real system API (full-screen window state, Focus/DND status).
    final class StubInterruptionSource: BreakInterruptionSource, @unchecked Sendable {
        var isFullScreen = false
        var isDoNotDisturb = false

        func isFullScreenAppActive() -> Bool { isFullScreen }
        func isDoNotDisturbActive() -> Bool { isDoNotDisturb }
    }

    private func makeScheduler(
        workDuration: TimeInterval = 20 * 60,
        breakDuration: TimeInterval = 5 * 60,
        source: StubInterruptionSource
    ) -> (BreakScheduler, FakeClock) {
        let clock = FakeClock()
        let strategy = SimpleCycleSchedule(workDuration: workDuration, breakDuration: breakDuration)
        let scheduler = BreakScheduler(
            strategy: strategy,
            clock: { clock.now },
            interruptionSource: source
        )
        return (scheduler, clock)
    }

    @Test("a rest that would trigger while a full-screen app is active is postponed instead of presented")
    func postponesRestWhileFullScreenAppIsActive() {
        let source = StubInterruptionSource()
        source.isFullScreen = true
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, source: source)

        clock.advance(by: 20 * 60)
        scheduler.tick()

        #expect(scheduler.phase == .working)
        #expect(scheduler.isRestPending)
    }

    @Test("a rest that would trigger while Do Not Disturb/Focus is active is postponed instead of presented")
    func postponesRestWhileDoNotDisturbIsActive() {
        let source = StubInterruptionSource()
        source.isDoNotDisturb = true
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, source: source)

        clock.advance(by: 20 * 60)
        scheduler.tick()

        #expect(scheduler.phase == .working)
        #expect(scheduler.isRestPending)
    }

    @Test("a postponed rest keeps being held back for as long as the interrupting condition remains")
    func stayPostponedWhileConditionPersists() {
        let source = StubInterruptionSource()
        source.isFullScreen = true
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, source: source)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)

        clock.advance(by: 30 * 60)
        scheduler.tick()

        #expect(scheduler.phase == .working)
        #expect(scheduler.isRestPending)
    }

    @Test("a postponed rest starts automatically, at full length, the moment the interrupting condition clears")
    func startsPostponedRestAutomaticallyOnceClear() {
        let source = StubInterruptionSource()
        source.isFullScreen = true
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60, source: source)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)
        #expect(scheduler.isRestPending)

        clock.advance(by: 45 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)

        source.isFullScreen = false
        scheduler.tick()

        #expect(scheduler.phase == .resting)
        #expect(!scheduler.isRestPending)
        #expect(scheduler.remaining == 5 * 60)
    }

    @Test("clearing Do Not Disturb also releases a rest that was postponed because of it")
    func startsPostponedRestAutomaticallyOnceDoNotDisturbClears() {
        let source = StubInterruptionSource()
        source.isDoNotDisturb = true
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60, source: source)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.isRestPending)

        source.isDoNotDisturb = false
        scheduler.tick()

        #expect(scheduler.phase == .resting)
        #expect(scheduler.remaining == 5 * 60)
    }

    @Test("the work period following a postponed-then-released rest still runs a full, unshortened duration")
    func doesNotShortenTheNextWorkPeriod() {
        let source = StubInterruptionSource()
        source.isFullScreen = true
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60, source: source)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        clock.advance(by: 10 * 60)
        source.isFullScreen = false
        scheduler.tick()
        #expect(scheduler.phase == .resting)

        clock.advance(by: 5 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)
        #expect(scheduler.remaining == 20 * 60)
    }

    @Test("isRestPending stays false and the rest triggers normally when nothing is interrupting")
    func triggersNormallyWhenNotInterrupting() {
        let source = StubInterruptionSource()
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60, source: source)

        clock.advance(by: 20 * 60)
        scheduler.tick()

        #expect(scheduler.phase == .resting)
        #expect(!scheduler.isRestPending)
    }
}
