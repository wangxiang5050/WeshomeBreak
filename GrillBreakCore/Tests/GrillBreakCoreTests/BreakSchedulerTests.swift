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

    @Test("pausing freezes elapsed time even as the clock keeps advancing")
    func pausingFreezesElapsed() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.pause()
        #expect(scheduler.isPaused)
        #expect(scheduler.elapsed == 5 * 60)

        clock.advance(by: 10 * 60)
        #expect(scheduler.elapsed == 5 * 60)
        #expect(scheduler.remaining == 15 * 60)
    }

    @Test("tick is a no-op while paused, even past the phase duration")
    func tickIsNoOpWhilePaused() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.pause()

        clock.advance(by: 30 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)
    }

    @Test("resuming picks up elapsed time from where it was paused")
    func resumingContinuesFromPauseState() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.pause()

        clock.advance(by: 10 * 60)
        scheduler.resume()
        #expect(!scheduler.isPaused)
        #expect(scheduler.elapsed == 5 * 60)

        clock.advance(by: 15 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)
    }

    @Test("pausing twice in a row has no additional effect")
    func pausingTwiceIsIdempotent() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.pause()
        clock.advance(by: 2 * 60)
        scheduler.pause()

        #expect(scheduler.elapsed == 5 * 60)
    }

    @Test("resuming while not paused has no effect")
    func resumingWithoutPauseIsNoOp() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.resume()

        #expect(!scheduler.isPaused)
        #expect(scheduler.elapsed == 5 * 60)
    }

    @Test("skipping ends the rest immediately and requires a full work duration before the next rest")
    func skipEndsRestAndRequiresFullWorkDuration() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)

        clock.advance(by: 1 * 60)
        scheduler.skip()
        #expect(scheduler.phase == .working)
        #expect(scheduler.remaining == 20 * 60)

        clock.advance(by: 19 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)

        clock.advance(by: 1 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)
    }

    @Test("skip is a no-op while working")
    func skipIsNoOpWhileWorking() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.skip()

        #expect(scheduler.phase == .working)
        #expect(scheduler.elapsed == 5 * 60)
    }

    @Test("delaying re-triggers the same rest after the delay interval, not a full work duration")
    func delayRetriggersSameRestAfterInterval() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)

        scheduler.delay(by: 5 * 60)
        #expect(scheduler.phase == .working)
        #expect(scheduler.remaining == 5 * 60)

        clock.advance(by: 4 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)

        clock.advance(by: 1 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)
        #expect(scheduler.remaining == 5 * 60)
    }

    @Test("delay can be called repeatedly with no limit, each call pushing the rest back further")
    func delayCanBeCalledRepeatedly() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)

        for _ in 0..<3 {
            scheduler.delay(by: 5 * 60)
            #expect(scheduler.phase == .working)

            clock.advance(by: 5 * 60)
            scheduler.tick()
            #expect(scheduler.phase == .resting)
        }
    }

    @Test("delay is a no-op while working")
    func delayIsNoOpWhileWorking() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.delay(by: 5 * 60)

        #expect(scheduler.phase == .working)
        #expect(scheduler.elapsed == 5 * 60)
    }

    @Test("starting a break now ends the work period immediately and starts a full-length rest")
    func startBreakNowStartsFullLengthRestImmediately() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 5 * 60)
        scheduler.startBreakNow()

        #expect(scheduler.phase == .resting)
        #expect(scheduler.remaining == 5 * 60)
    }

    @Test("the work period after a manually started break still runs a full, unshortened duration")
    func startBreakNowDoesNotShortenTheNextWorkPeriod() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 5 * 60)
        scheduler.startBreakNow()
        #expect(scheduler.phase == .resting)

        clock.advance(by: 5 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)
        #expect(scheduler.remaining == 20 * 60)

        clock.advance(by: 19 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .working)

        clock.advance(by: 1 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)
    }

    @Test("starting a break now is a no-op while already resting")
    func startBreakNowIsNoOpWhileResting() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)

        clock.advance(by: 1 * 60)
        scheduler.startBreakNow()

        #expect(scheduler.phase == .resting)
        #expect(scheduler.remaining == 4 * 60)
    }

    @Test("starting a break now is a no-op while paused, leaving the frozen state untouched")
    func startBreakNowIsNoOpWhilePaused() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 5 * 60)
        scheduler.pause()

        clock.advance(by: 2 * 60)
        scheduler.startBreakNow()

        #expect(scheduler.phase == .working)
        #expect(scheduler.isPaused)
        #expect(scheduler.elapsed == 5 * 60)
    }

    @Test("updating the strategy immediately changes the current phase's remaining time")
    func updatingStrategyAffectsCurrentPhaseImmediately() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60)

        clock.advance(by: 5 * 60)
        scheduler.updateStrategy(SimpleCycleSchedule(workDuration: 30 * 60, breakDuration: 5 * 60))

        #expect(scheduler.remaining == 25 * 60)
    }

    @Test("updating the strategy changes the duration used once the next phase starts")
    func updatingStrategyAffectsSubsequentPhases() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        scheduler.updateStrategy(SimpleCycleSchedule(workDuration: 20 * 60, breakDuration: 10 * 60))

        clock.advance(by: 20 * 60)
        scheduler.tick()
        #expect(scheduler.phase == .resting)
        #expect(scheduler.remaining == 10 * 60)
    }

    @Test("updating the strategy while a delay override is active leaves the override in place")
    func updatingStrategyDoesNotClearAnActiveDelayOverride() {
        let (scheduler, clock) = makeScheduler(workDuration: 20 * 60, breakDuration: 5 * 60)

        clock.advance(by: 20 * 60)
        scheduler.tick()
        scheduler.delay(by: 3 * 60)
        #expect(scheduler.remaining == 3 * 60)

        scheduler.updateStrategy(SimpleCycleSchedule(workDuration: 99 * 60, breakDuration: 5 * 60))
        #expect(scheduler.remaining == 3 * 60)
    }
}
