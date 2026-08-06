import Foundation
import Testing
@testable import GrillBreakCore

@Suite("BreakScheduler")
struct BreakSchedulerTests {

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

    private func makeScheduler(
        workDuration: TimeInterval = 20 * 60,
        breakDuration: TimeInterval = 5 * 60,
        startingPhase: BreakPhase = .working
    ) -> (BreakScheduler, FakeClock) {
        let clock = FakeClock()
        let strategy = SimpleCycleSchedule(workDuration: workDuration, breakDuration: breakDuration)
        let scheduler = BreakScheduler(strategy: strategy, startingPhase: startingPhase, clock: { clock.now })
        return (scheduler, clock)
    }

    @Test("starts in the working phase by default")
    func startsWorking() {
        let (scheduler, _) = makeScheduler()
        #expect(scheduler.phase == .working)
    }

    @Test("stays in working phase before the work duration elapses")
    func staysWorkingBeforeDurationElapses() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)
        clock.advance(by: 19 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)
    }

    @Test("transitions from working to resting once the work duration elapses")
    func transitionsToRestingAfterWorkDuration() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)
        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)
    }

    @Test("transitions from resting back to working once the break duration elapses")
    func transitionsBackToWorkingAfterBreakDuration() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)
        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)

        clock.advance(by: 5 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)
    }

    @Test("cycles through multiple work/rest rounds")
    func cyclesThroughMultipleRounds() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        for _ in 0..<3 {
            clock.advance(by: 20 * 60)
            scheduler.tick()
            #expect(scheduler.phase == .resting)

            clock.advance(by: 5 * 60)
            scheduler.tick()
            #expect(scheduler.phase == .working)
        }
    }

    @Test("advancing past multiple phase durations in one jump still lands on the correct phase")
    func advancingPastMultiplePhasesInOneJump() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 20 * 60 + 5 * 60 + 20 * 60)
        scheduler.tick()

        #expect(scheduler.phase == .resting)
    }

    @Test("remaining time counts down within the current phase")
    func remainingCountsDown() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        #expect(scheduler.remaining == 20 * 60)

        clock.advance(by: 5 * 60)
        #expect(scheduler.remaining == 15 * 60)
    }

    @Test("remaining time never goes negative once a phase has elapsed but tick hasn't run")
    func remainingNeverNegative() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 25 * 60)
        #expect(scheduler.remaining == 0)
    }
}
