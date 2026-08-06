import Testing
import Foundation
@testable import WhiteoutCore

/// A crashed skier built by hand, for the cases a real descent reaches rarely or never.
private func crashedState(velocityX: Double, distanceM: Double = 400) -> SkierState {
    SkierState(
        distanceM: distanceM,
        altitudeM: -120,
        velocityX: velocityX,
        velocityY: 0,
        rotation: -0.3,
        angularVelocity: 0,
        isGrounded: true,
        hasCrashed: true,
        airTimeS: 0,
        totalAirTimeS: 2.4,
        flips: 1,
        jumpRotation: 0,
        instability: 1
    )
}

/// Advances only the crash weight, which is all `hasSettled` reads from the animator.
private func collapsed(over seconds: Double, delta: Double = 1.0 / 60) -> SkierAnimator {
    var animator = SkierAnimator.idle
    let state = crashedState(velocityX: 0)
    for _ in 0..<Int((seconds / delta).rounded()) {
        animator = animator.advanced(for: state, cues: .idle, landingImpact: 0, delta: delta)
    }
    return animator
}

/// The mountain a `descend(seed:snowState:)` ran over.
///
/// Rebuilt rather than threaded back out of the harness. `TerrainGenerator` is a value type
/// and a pure function of `(seed, snowState)`, so this is the same mountain by construction —
/// the property the whole replay and server-verification story already rests on.
private func mountain(seed: UInt64, snow: SnowState) -> TerrainGenerator {
    TerrainGenerator(seed: seed, snowState: snow)
}

private func firstSettledIndex(_ frames: [Frame], terrain: TerrainGenerator) -> Int? {
    frames.firstIndex {
        RunOutcome.hasSettled($0.state, collapse: $0.animator.crash, terrain: terrain)
    }
}

/// Drives a real descent to a real stall and hands back the frame it stopped on.
///
/// Hand-building a stalled state is possible but proves less: the interesting question is
/// whether the *simulation* can still reach a standstill nothing can leave, so the fixtures
/// that matter come out of an actual run. Seed 777 on packed snow, never tucking, stops at
/// ~392.8 m — carving scrubs enough speed that the counter-slope there is unclearable.
private func stalledRun(
    seed: UInt64 = 777,
    snow: SnowState = .packed
) -> (state: SkierState, terrain: TerrainGenerator)? {
    let terrain = mountain(seed: seed, snow: snow)
    let physics = SnowPhysics.profile(for: snow)
    var state = SkierState.start(on: terrain)
    for _ in 0..<9_000 {
        state = SkierSimulation.step(
            state, input: SkierInput(isHolding: false),
            terrain: terrain, physics: physics, delta: 1.0 / 60
        )
        if state.hasCrashed { return nil }
        if RunOutcome.hasStalled(state, terrain: terrain) { return (state, terrain) }
    }
    return nil
}

private let testPeak = Peak.all[0]

/// Conditions carrying a chosen snow state, so `RunScore.from` can be exercised as written
/// rather than re-implemented inside the test.
private func conditions(snow: SnowState) -> RunConditions {
    let weather = MountainWeather(
        elevationM: 2_400, temperatureC: -6, freshSnowCm: 5, snowfallCmPerHour: 0,
        isRainingAtAltitude: false, windSpeedKmh: 12, windGustKmh: 18,
        windDirectionDeg: 280, visibilityM: 15_000, cloudCoverPercent: 40,
        sunAltitudeDeg: 30, localHour: 11, maxTemperature24hC: -3, minTemperature24hC: -11
    )
    return RunConditions(
        seed: 17,
        placeName: "Test Range",
        weather: weather,
        snowState: snow,
        physics: .profile(for: snow),
        palette: PaletteGenerator.palette(for: weather, state: snow),
        resolvedAt: Date(timeIntervalSince1970: 0)
    )
}

@Suite("Run outcome — lifecycle")
struct RunOutcomeLifecycleTests {

    @Test("a settled run cannot drift", arguments: [1.0 / 120, 1.0 / 60, 1.0 / 30])
    func aSettledRunCannotDrift(delta: Double) {
        // The load-bearing assertion of the whole design, in two halves.
        //
        // The crash must first actually *reach* a dead stop. Starting the fixture at zero would
        // make the second half unfalsifiable: zero is a fixed point of any decay, including a
        // multiplicative one, so a `coast` that eased asymptotically instead of clamping with
        // `max(0, …)` would sail through — while in a real run `velocityX` never reached zero
        // and the summary never appeared at all.
        let terrain = TerrainGenerator(seed: 17, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)

        var settled = crashedState(velocityX: 12)
        var frames = 0
        while settled.velocityX > 0 && frames < 600 {
            settled = SkierSimulation.step(
                settled, input: SkierInput(isHolding: false),
                terrain: terrain, physics: physics, delta: delta
            )
            frames += 1
        }
        #expect(settled.velocityX == 0, "the slide never reached a dead stop at delta \(delta)")

        // And once stopped, every field is a constant expression of itself — which is what makes
        // a score read on any later frame identical to one read on the first, and why nothing
        // anywhere is snapshotted.
        for holding in [true, false] {
            let next = SkierSimulation.step(
                settled,
                input: SkierInput(isHolding: holding),
                terrain: terrain,
                physics: physics,
                delta: delta
            )
            #expect(next == settled, "holding \(holding) at delta \(delta)")
        }
    }

    @Test("a run stalled on a counter-slope is over")
    func aRunStalledOnACounterSlopeIsOver() {
        // The inverse of what this test asserted before T-116. It used to pin the stall *out*
        // of scope — a dead stop with no crash did not summarise, which is precisely the defect:
        // the run sat motionless forever with no ending and no way to restart.
        guard let (stalled, terrain) = stalledRun() else {
            Issue.record("the fixture run no longer reaches a stall")
            return
        }
        #expect(!stalled.hasCrashed, "a stall is not a crash")
        #expect(stalled.velocityX == 0)
        #expect(terrain.contactAngle(at: stalled.distanceM) >= 0)

        // Independent of the collapse weight in both directions: there is no fold to wait for,
        // so a stall must not inherit the crash's beat — at collapse 0, which is what the
        // animator actually reports for an uncrashed skier, the run is over immediately.
        #expect(RunOutcome.hasSettled(stalled, collapse: 0, terrain: terrain))
        #expect(RunOutcome.hasSettled(stalled, collapse: 1, terrain: terrain))
    }

    @Test("a skier stopped on a descending surface is not stalled")
    func aSkierStoppedOnADescendingSurfaceIsNotStalled() {
        // The heir to what `aRunThatNeverCrashedIsNeverOver` was really protecting, and the only
        // assertion in the suite that fails if the counter-slope clause is dropped from
        // `hasStalled`. Without it, "stopped and uncrashed" would end a run that gravity is
        // about to restart — and the summary would flicker back into a live HUD a frame later.
        let terrain = mountain(seed: 777, snow: .packed)
        let physics = SnowPhysics.profile(for: .packed)

        // A genuinely downhill metre of this mountain, found rather than assumed: the terrain is
        // generated, so hardcoding a distance would pin a coordinate that means nothing.
        var downhill: Double?
        var x = 10.0
        while x < 3_000 {
            if terrain.contactAngle(at: x) < -0.05 { downhill = x; break }
            x += 0.25
        }
        guard let at = downhill else {
            Issue.record("no descending metre found on the fixture mountain")
            return
        }

        let stopped = SkierState(
            distanceM: at, altitudeM: terrain.height(at: at), velocityX: 0, velocityY: 0,
            rotation: terrain.contactAngle(at: at), angularVelocity: 0, isGrounded: true,
            hasCrashed: false, airTimeS: 0, totalAirTimeS: 3.1, flips: 1, jumpRotation: 0,
            instability: 0.04
        )
        #expect(!RunOutcome.hasStalled(stopped, terrain: terrain))
        #expect(!RunOutcome.hasSettled(stopped, collapse: 0, terrain: terrain))
        #expect(!RunOutcome.hasSettled(stopped, collapse: 1, terrain: terrain))

        // And the reason it must not be called over: gravity does restart it.
        let next = SkierSimulation.step(
            stopped, input: SkierInput(isHolding: false),
            terrain: terrain, physics: physics, delta: 1.0 / 60
        )
        #expect(next.velocityX > 0, "a skier on a descending surface is not stuck")
    }

    @Test("a stalled run cannot restart itself", arguments: [1.0 / 120, 1.0 / 60, 1.0 / 30, 1.0 / 20])
    func aStalledRunCannotRestartItself(delta: Double) {
        // The stall's half of `aSettledRunCannotDrift`, and the claim `hasStalled`'s comment
        // makes: the state is its own successor, so a score read on any later frame equals the
        // one read on the first. Nothing is snapshotted anywhere on the strength of this.
        //
        // Both inputs matter. A held tuck at a standstill is the case that would break it if
        // instability still built at zero speed — the skier would eventually crash out of a
        // summary that was already on screen.
        guard let (stalled, terrain) = stalledRun() else {
            Issue.record("the fixture run no longer reaches a stall")
            return
        }
        let physics = SnowPhysics.profile(for: .packed)

        for holding in [true, false] {
            var state = stalled
            for frame in 0..<1_200 {
                state = SkierSimulation.step(
                    state, input: SkierInput(isHolding: holding),
                    terrain: terrain, physics: physics, delta: delta
                )
                #expect(state.distanceM == stalled.distanceM, "moved at frame \(frame), holding \(holding)")
                #expect(state.totalAirTimeS == stalled.totalAirTimeS)
                #expect(state.flips == stalled.flips)
                #expect(!state.hasCrashed, "crashed out of a finished run at frame \(frame)")
                #expect(RunOutcome.hasStalled(state, terrain: terrain), "un-stalled at frame \(frame)")
            }
        }
    }

    @Test("a crash that stops almost instantly still gets its collapse")
    func aSlowCrashStillGetsItsCollapse() {
        // The test the collapse term exists for. A crash entered at walking pace stops in a
        // couple of frames, so gating on `velocityX == 0` alone would drop the card over a
        // skier still standing upright. This is the only assertion in the suite that fails if
        // `collapseFloor` is removed.
        let stopped = crashedState(velocityX: 0)
        // Any mountain will do: a crashed skier never reaches the stall clause, so terrain here
        // is only the argument the signature demands.
        let terrain = mountain(seed: 17, snow: .packed)

        #expect(!RunOutcome.hasSettled(stopped, collapse: 0, terrain: terrain))
        #expect(!RunOutcome.hasSettled(stopped, collapse: RunOutcome.collapseFloor - 0.01, terrain: terrain))
        #expect(RunOutcome.hasSettled(stopped, collapse: RunOutcome.collapseFloor, terrain: terrain))
    }

    @Test("the collapse floor matches the animator's crash rate")
    func theCollapseFloorMatchesTheAnimatorsCrashRate() {
        // An independent reference for the 0.233 s beat. `SkierAnimator.Rate` is private, so
        // without this the coupling between the fold and the pause lives only in a comment and
        // can drift the moment someone retunes the collapse.
        let expected = log(10.0) / 10.0
        let delta = 1.0 / 60

        var animator = SkierAnimator.idle
        let state = crashedState(velocityX: 0)
        var elapsed = 0.0
        while animator.crash < RunOutcome.collapseFloor && elapsed < 2 {
            animator = animator.advanced(for: state, cues: .idle, landingImpact: 0, delta: delta)
            elapsed += delta
        }

        #expect(abs(elapsed - expected) <= delta, "reached the floor at \(elapsed)s, expected ~\(expected)s")
    }

    @Test("when the run ends does not depend on the frame rate")
    func theEndingIsFrameRateIndependent() {
        // Mirrors `easingIsFrameRateIndependent`. Coasting the same crash is isolated from
        // terrain here on purpose: stepping a real descent at three rates crosses the
        // instability threshold in three different places, which measures the simulation
        // rather than the ending.
        let terrain = TerrainGenerator(seed: 17, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)

        // Returns nil if the run never ended, so a timeout fails loudly instead of being
        // compared against another timeout — two runs that both never finish otherwise agree
        // to within a frame and report perfect frame-rate independence.
        func secondsToEnd(delta: Double) -> Double? {
            var state = crashedState(velocityX: 11)
            var animator = SkierAnimator.idle
            var elapsed = 0.0
            while elapsed < 5 {
                state = SkierSimulation.step(
                    state, input: SkierInput(isHolding: false),
                    terrain: terrain, physics: physics, delta: delta
                )
                animator = animator.advanced(for: state, cues: .idle, landingImpact: 0, delta: delta)
                elapsed += delta
                if RunOutcome.hasSettled(state, collapse: animator.crash, terrain: terrain) { return elapsed }
            }
            return nil
        }

        guard let coarse = secondsToEnd(delta: 1.0 / 30),
              let medium = secondsToEnd(delta: 1.0 / 60),
              let fine = secondsToEnd(delta: 1.0 / 120) else {
            Issue.record("the crash never settled at one or more frame rates")
            return
        }
        #expect(abs(coarse - medium) <= 1.0 / 30)
        #expect(abs(coarse - fine) <= 1.0 / 30, "1/30 ended at \(coarse)s, 1/120 at \(fine)s")
    }

    @Test("a jittering frame rate does not change when the run ends")
    func aJitteringFrameRateDoesNotChangeWhenTheRunEnds() {
        // The real loop never delivers a fixed delta — `MountainScene` clamps to 1/20 and
        // passes whatever the display gave it. A fixed-delta test cannot see a rule that
        // happens to hold only on even steps.
        let terrain = TerrainGenerator(seed: 17, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)

        // Nil rather than the timeout, for the same reason as above: two runs that never end
        // agree perfectly and would report success.
        func secondsToEnd(deltaAt: (Int) -> Double) -> Double? {
            var state = crashedState(velocityX: 11)
            var animator = SkierAnimator.idle
            var elapsed = 0.0
            var frame = 0
            while elapsed < 5 {
                let delta = deltaAt(frame)
                state = SkierSimulation.step(
                    state, input: SkierInput(isHolding: false),
                    terrain: terrain, physics: physics, delta: delta
                )
                animator = animator.advanced(for: state, cues: .idle, landingImpact: 0, delta: delta)
                elapsed += delta
                frame += 1
                if RunOutcome.hasSettled(state, collapse: animator.crash, terrain: terrain) { return elapsed }
            }
            return nil
        }

        // A fixed tape, not randomness: reproducible, and it spans the clamp's whole range.
        guard let steady = secondsToEnd(deltaAt: { _ in 1.0 / 60 }),
              let jittered = secondsToEnd(deltaAt: { 1.0 / [120.0, 60, 20, 45, 90, 30][$0 % 6] }) else {
            Issue.record("the crash never settled")
            return
        }
        #expect(abs(steady - jittered) < 0.1, "steady \(steady)s vs jittered \(jittered)s")
    }

    @Test("a zero delta is a no-op")
    func aZeroDeltaIsANoOp() {
        // Both the first frame (`guard lastFrameTime > 0`) and returning from the background
        // can present a zero step.
        let terrain = TerrainGenerator(seed: 17, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)
        let state = crashedState(velocityX: 6)
        let animator = collapsed(over: 0.1)

        let stepped = SkierSimulation.step(
            state, input: SkierInput(isHolding: false),
            terrain: terrain, physics: physics, delta: 0
        )
        let advanced = animator.advanced(for: state, cues: .idle, landingImpact: 0, delta: 0)

        #expect(stepped.velocityX == state.velocityX)
        #expect(advanced == animator)
        #expect(RunOutcome.hasSettled(stepped, collapse: advanced.crash, terrain: terrain)
                == RunOutcome.hasSettled(state, collapse: animator.crash, terrain: terrain))
    }

    @Test("the ending is monotone")
    func theEndingIsMonotone() {
        // A summary that could flicker back into a live HUD would be worse than no summary.
        let terrain = TerrainGenerator(seed: 17, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)
        var state = crashedState(velocityX: 0)
        var animator = collapsed(over: 0.5)
        #expect(RunOutcome.hasSettled(state, collapse: animator.crash, terrain: terrain))

        for frame in 0..<600 {
            state = SkierSimulation.step(
                state, input: SkierInput(isHolding: frame % 2 == 0),
                terrain: terrain, physics: physics, delta: 1.0 / 60
            )
            animator = animator.advanced(for: state, cues: .idle, landingImpact: 0, delta: 1.0 / 60)
            #expect(RunOutcome.hasSettled(state, collapse: animator.crash, terrain: terrain), "frame \(frame)")
        }
    }

    @Test("a crash reported while airborne still ends the run")
    func aCrashReportedWhileAirborneStillEndsTheRun() {
        // No path through `SkierSimulation` produces this today — both crash constructors and
        // `coast` set `isGrounded: true`. Asserting it anyway means a future physics change
        // breaks a test rather than silently leaving the summary unreachable.
        let airborne = SkierState(
            distanceM: 500, altitudeM: -100, velocityX: 0, velocityY: 0,
            rotation: 0, angularVelocity: 0, isGrounded: false, hasCrashed: true,
            airTimeS: 1.2, totalAirTimeS: 3, flips: 2, jumpRotation: 0, instability: 1
        )
        #expect(RunOutcome.hasSettled(airborne, collapse: 1, terrain: mountain(seed: 17, snow: .packed)))
    }

    @Test("a motionless skier in the air has not stalled")
    func aMotionlessSkierInTheAirHasNotStalled() {
        // The twin of `aCrashReportedWhileAirborneStillEndsTheRun`, and for the same reason: no
        // path through `SkierSimulation` produces this today — a launch requires clearing the
        // lip, so nothing in flight has zero horizontal speed — but without this the
        // `isGrounded` clause of `hasStalled` is unfalsifiable, and deleting it would leave the
        // whole suite green while runs ended in mid-air at the top of a jump.
        let terrain = mountain(seed: 777, snow: .packed)
        // Over a rising metre, so the counter-slope clause is satisfied and `isGrounded` is
        // genuinely the only thing standing between this state and a summary card.
        var uphill: Double?
        var x = 10.0
        while x < 3_000 {
            if terrain.contactAngle(at: x) > 0.05 { uphill = x; break }
            x += 0.25
        }
        guard let at = uphill else {
            Issue.record("no rising metre found on the fixture mountain")
            return
        }

        let falling = SkierState(
            distanceM: at, altitudeM: terrain.height(at: at) + 6, velocityX: 0, velocityY: -4,
            rotation: 0.2, angularVelocity: 0, isGrounded: false, hasCrashed: false,
            airTimeS: 0.6, totalAirTimeS: 0.6, flips: 0, jumpRotation: 0, instability: 0.1
        )
        #expect(terrain.contactAngle(at: at) >= 0, "the fixture must isolate the grounded clause")
        #expect(!RunOutcome.hasStalled(falling, terrain: terrain))
        #expect(!RunOutcome.hasSettled(falling, collapse: 0, terrain: terrain))
    }

    @Test("the headline names which crash it was")
    func theHeadlineNamesWhichCrashItWas() {
        let terrain = mountain(seed: 17, snow: .packed)
        let riding = SkierState.start(on: terrain)
        let airborne = SkierState(
            distanceM: 300, altitudeM: -80, velocityX: 20, velocityY: -14,
            rotation: 1.1, angularVelocity: -4.4, isGrounded: false, hasCrashed: false,
            airTimeS: 0.7, totalAirTimeS: 0.7, flips: 0, jumpRotation: -3, instability: 0.2
        )
        let crashed = crashedState(velocityX: 8)

        #expect(RunOutcome.reason(previous: riding, current: crashed, terrain: terrain) == .caughtAnEdge)
        #expect(RunOutcome.reason(previous: airborne, current: crashed, terrain: terrain) == .blewTheLanding)
        // The rendered text, not only the case. This is what the player reads, and the whole
        // point of deriving the cause was that the old build printed the wrong one — a suite
        // that checks only the enum would not notice the two strings being swapped.
        #expect(RunOutcome.Reason.caughtAnEdge.headline == "CAUGHT AN EDGE")
        #expect(RunOutcome.Reason.blewTheLanding.headline == "BLEW THE LANDING")
        // Nothing on a frame that is not the edge, and no re-latching once already crashed —
        // the scene keeps the first answer for the whole of the summary.
        #expect(RunOutcome.reason(previous: riding, current: riding, terrain: terrain) == nil)
        #expect(RunOutcome.reason(previous: crashed, current: crashed, terrain: terrain) == nil)
    }

    @Test("the card and the share line name the same conditions")
    func theCardAndTheShareLineNameTheSameConditions() {
        let score = RunScore(
            distanceM: 4_120, airTimeS: 6.4, flips: 2,
            snowState: .crust, peak: testPeak, endedInCrash: true
        )
        #expect(score.conditionsLine.contains(SnowState.crust.displayName))
        #expect(score.conditionsLine.contains(testPeak.name))
        #expect(score.shareLine.contains(SnowState.crust.displayName))
        #expect(score.shareLine.contains(testPeak.name))
    }
}

@Suite("Run outcome — over a real run")
struct RunOutcomeRunTests {

    /// A held descent and the mountain it ran over, together — every question about a run
    /// ending now needs both, and pairing them here is what stops a test asking one mountain
    /// about another one's frames.
    private func heldRun(
        seed: UInt64,
        snow: SnowState = .packed
    ) -> (frames: [Frame], terrain: TerrainGenerator) {
        (descend(seed: seed, snowState: snow, isHolding: { _ in true }), mountain(seed: seed, snow: snow))
    }

    @Test("a held descent reaches a crash, a slide and a settled end")
    func theRunReachesACrashASlideAndASettledEnd() {
        // Guards every assertion below: without it they would all pass vacuously over a run
        // that never crashed at all.
        let (frames, terrain) = heldRun(seed: 17)

        #expect(frames.contains { $0.state.hasCrashed && $0.state.velocityX > 0 })
        guard let settled = firstSettledIndex(frames, terrain: terrain) else {
            Issue.record("the run never settled")
            return
        }
        #expect(frames[settled].state.distanceM > 0)
    }

    @Test("the summary waits for the skier to stop sliding")
    func theSummaryWaitsForTheSkierToStopSliding() {
        let (frames, terrain) = heldRun(seed: 17)
        for frame in frames where frame.state.hasCrashed && frame.state.velocityX > 0 {
            #expect(!RunOutcome.hasSettled(frame.state, collapse: frame.animator.crash, terrain: terrain))
        }
    }

    @Test("the fold is legible before the summary appears")
    func theFoldIsLegibleBeforeTheSummaryAppears() {
        let (frames, terrain) = heldRun(seed: 17)
        for frame in frames where frame.animator.crash < RunOutcome.collapseFloor {
            #expect(!RunOutcome.hasSettled(frame.state, collapse: frame.animator.crash, terrain: terrain))
        }
    }

    @Test("the summary matches what the run actually did")
    func theSummaryMatchesWhatTheRunActuallyDid() {
        // `RunScoreTests` only ever exercises hand-built scores, so nothing until now has
        // checked that a score built from a real final state reports that run.
        let (frames, terrain) = heldRun(seed: 17, snow: .crust)
        guard let index = firstSettledIndex(frames, terrain: terrain) else {
            Issue.record("the run never settled")
            return
        }
        let state = frames[index].state
        // Through `RunScore.from`, the production mapping — hand-rolling the same initialiser
        // inside the test would only read back the arguments it had just passed in.
        let score = RunScore.from(state, conditions: conditions(snow: .crust), peak: Peak.all[0])

        #expect(score.snowState == .crust)
        #expect(score.distanceM == state.distanceM)
        #expect(score.airTimeS == state.totalAirTimeS)
        #expect(score.flips == state.flips)
        #expect(score.endedInCrash)
        #expect(score.distanceM > 0)
    }

    @Test("the score stops changing once the run is over")
    func theScoreStopsChangingOnceTheRunIsOver() {
        // The property that lets the card read live telemetry instead of a captured snapshot.
        let (frames, terrain) = heldRun(seed: 17)
        guard let index = firstSettledIndex(frames, terrain: terrain) else {
            Issue.record("the run never settled")
            return
        }

        func score(_ frame: Frame) -> RunScore {
            RunScore(
                distanceM: frame.state.distanceM, airTimeS: frame.state.totalAirTimeS,
                flips: frame.state.flips, snowState: .packed, peak: Peak.all[0],
                endedInCrash: frame.state.hasCrashed
            )
        }

        let first = score(frames[index])
        for frame in frames[index...] {
            #expect(score(frame) == first)
        }
    }

    @Test("the run ends exactly once")
    func theRunEndsExactlyOnce() {
        let (frames, terrain) = heldRun(seed: 17)
        let settled = frames.map { RunOutcome.hasSettled($0.state, collapse: $0.animator.crash, terrain: terrain) }
        guard let first = settled.firstIndex(of: true) else {
            Issue.record("the run never settled")
            return
        }
        #expect(settled[first...].allSatisfy { $0 })
    }

    @Test("evaluating the ending never writes to the simulation")
    func theEndingNeverWritesToTheSimulation() {
        // Invariant 3: feel never writes to physics. The two loops must be *interleaved* to mean
        // anything — asking the question after a descent has already finished cannot observe a
        // side effect on that descent, and only re-tests determinism.
        let terrain = TerrainGenerator(seed: 4_242, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)

        func run(askingTheQuestion: Bool) -> [SkierState] {
            var state = SkierState.start(on: terrain)
            var animator = SkierAnimator.idle
            var states: [SkierState] = []
            for _ in 0..<1_200 {
                state = SkierSimulation.step(
                    state, input: SkierInput(isHolding: true),
                    terrain: terrain, physics: physics, delta: 1.0 / 60
                )
                animator = animator.advanced(
                    for: state, cues: .idle, landingImpact: 0, delta: 1.0 / 60
                )
                if askingTheQuestion {
                    _ = RunOutcome.hasSettled(state, collapse: animator.crash, terrain: terrain)
                    _ = RunOutcome.reason(previous: states.last ?? state, current: state, terrain: terrain)
                }
                states.append(state)
            }
            return states
        }

        #expect(run(askingTheQuestion: true) == run(askingTheQuestion: false))
    }

    @Test("endings are reproducible from the seed")
    func endingsAreReproducibleFromTheSeed() {
        // The property ghosts and server-side score verification both rest on: a run is fully
        // described by its seed and input tape, so where it ended must be too.
        let (a, terrain) = heldRun(seed: 777)
        let (b, _) = heldRun(seed: 777)
        #expect(firstSettledIndex(a, terrain: terrain) == firstSettledIndex(b, terrain: terrain))
        #expect(a.map(\.state) == b.map(\.state))
    }

    @Test("every surface produces a scoreable run", arguments: SnowState.allCases)
    func everySurfaceProducesAScoreableRun(snow: SnowState) {
        // A held tuck ends in a crash on every surface, so every surface reaches a summary.
        //
        // The frame budget is 4,000 rather than the default 1,800 because of how wide the
        // spread is: a held tuck ends at frame ~55–130 on ice, crust and wind slab, ~700 on
        // packed, and ~2,700 on powder. Measured at 1/60, that is a run lasting under a second
        // and 15 m on boilerplate against 45 seconds and 950 m on powder — the same input,
        // sixty times the run, decided entirely by the day's snow.
        //
        // A held tuck crashes long before it can stall, so this says nothing about T-116 either
        // way — `noRunCanSitAtADeadStop` is what covers that, over tapes that do not tuck.
        let frames = descend(seed: 17, snowState: snow, isHolding: { _ in true }, frames: 4_000)
        guard let index = firstSettledIndex(frames, terrain: mountain(seed: 17, snow: snow)) else {
            Issue.record("\(snow) never settled")
            return
        }
        #expect(frames[index].state.distanceM > 0)
    }

    @Test("no run can sit at a dead stop")
    func noRunCanSitAtADeadStop() {
        // T-116's acceptance criterion, stated directly: the skier can no longer reach 0 km/h
        // and sit there. Not "stalls end" — *nothing* motionless is left unresolved, whichever
        // way it stopped.
        //
        // A full second of stillness rather than a single frame, because a crash is legitimately
        // motionless for the 0.233 s the collapse takes to read. One second clears that beat by
        // a factor of four while still being far shorter than a player's patience.
        //
        // The tapes matter more than the seeds here. A held tuck crashes out early on most
        // surfaces and never gets slow enough to stall, so a suite that only ever holds cannot
        // see this defect at all — which is exactly how it survived to M1.
        let tapes: [(name: String, tape: (Int) -> Bool)] = [
            ("never tucking", { _ in false }),
            ("pulsed", { ($0 % 60) < 40 })
        ]
        var stallsSeen = 0

        for seed in [UInt64(17), 777, 4_242, 90_210, 1] {
            for snow in SnowState.allCases {
                for (name, tape) in tapes {
                    let terrain = mountain(seed: seed, snow: snow)
                    let frames = descend(seed: seed, snowState: snow, isHolding: tape, frames: 9_000)

                    var stillFor = 0
                    for (index, frame) in frames.enumerated() {
                        guard frame.state.velocityX == 0 else {
                            stillFor = 0
                            continue
                        }
                        stillFor += 1
                        guard stillFor >= 60 else { continue }
                        #expect(
                            RunOutcome.hasSettled(frame.state, collapse: frame.animator.crash, terrain: terrain),
                            "seed \(seed) \(snow) \(name): motionless for a second at frame \(index), \(Int(frame.state.distanceM)) m, and the run is still not over"
                        )
                        if RunOutcome.hasStalled(frame.state, terrain: terrain) { stallsSeen += 1 }
                        break
                    }
                }
            }
        }
        // Without this the whole test passes vacuously the day the terrain stops producing
        // counter-slopes steep enough to stop anyone.
        #expect(stallsSeen > 0, "no run in the sweep actually stalled — the sweep proves nothing")
    }

    @Test("a stall is reported as a run that did not crash")
    func aStallIsReportedAsARunThatDidNotCrash() {
        // The distinction the whole ending rests on reaching the player. `RunScore.endedInCrash`
        // needed no new channel for this — a stall leaves `hasCrashed` false and the score reads
        // that field — but "needed no change" is a claim worth a test rather than a comment,
        // because the next person to touch `RunScore.from` will not know it was load-bearing.
        guard let (stalled, terrain) = stalledRun() else {
            Issue.record("the fixture run no longer reaches a stall")
            return
        }
        let score = RunScore.from(stalled, conditions: conditions(snow: .packed), peak: Peak.all[0])

        #expect(!score.endedInCrash)
        #expect(score.distanceM == stalled.distanceM)
        #expect(score.distanceM > 0)
        #expect(RunOutcome.hasSettled(stalled, collapse: 0, terrain: terrain))
    }

    @Test("the stall names itself, and is not a crash")
    func theStallNamesItselfAndIsNotACrash() {
        // The headline the player reads, and the flag the haptics key off. A stall firing
        // `feedback.crash()` would thump the taptic engine for an impact that never happened,
        // and a suite that checked only the enum case would not notice.
        guard let (stalled, terrain) = stalledRun() else {
            Issue.record("the fixture run no longer reaches a stall")
            return
        }
        // The frame before the stall: still moving, so the edge is a real transition rather
        // than two identical states compared against each other.
        let moving = SkierState(
            distanceM: stalled.distanceM - 0.4, altitudeM: stalled.altitudeM, velocityX: 1.2,
            velocityY: 0, rotation: stalled.rotation, angularVelocity: 0, isGrounded: true,
            hasCrashed: false, airTimeS: 0, totalAirTimeS: stalled.totalAirTimeS,
            flips: stalled.flips, jumpRotation: 0, instability: stalled.instability
        )

        #expect(RunOutcome.reason(previous: moving, current: stalled, terrain: terrain) == .ranOutOfSpeed)
        #expect(RunOutcome.Reason.ranOutOfSpeed.headline == "RAN OUT OF SPEED")
        #expect(!RunOutcome.Reason.ranOutOfSpeed.isCrash)
        #expect(RunOutcome.Reason.caughtAnEdge.isCrash)
        #expect(RunOutcome.Reason.blewTheLanding.isCrash)
        // And it latches exactly once: the scene keeps the first answer for the whole summary.
        #expect(RunOutcome.reason(previous: stalled, current: stalled, terrain: terrain) == nil)
    }

    @Test("both kinds of crash happen on a real mountain")
    func bothKindsOfCrashHappenOnARealMountain() {
        // The headline is only worth deriving if both answers actually occur in play.
        var seen: Set<RunOutcome.Reason> = []
        for seed in [UInt64(17), 777, 4_242, 90_210] {
            for snow in SnowState.allCases {
                let (frames, _) = heldRun(seed: seed, snow: snow)
                for (previous, current) in zip(frames, frames.dropFirst()) {
                    if let reason = RunOutcome.reason(previous: previous.state, current: current.state, terrain: mountain(seed: seed, snow: snow)) {
                        seen.insert(reason)
                    }
                }
            }
        }
        #expect(seen.contains(.caughtAnEdge))
        #expect(seen.contains(.blewTheLanding))
    }
}
