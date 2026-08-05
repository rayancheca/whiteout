import Testing
import Foundation
@testable import WhiteoutCore

/// Runs a fixed input for a number of frames at 60 Hz.
private func simulate(
    frames: Int,
    holding: Bool,
    state: SnowState,
    seed: UInt64 = 4_242,
    from initial: SkierState? = nil
) -> (state: SkierState, terrain: TerrainGenerator) {
    let terrain = TerrainGenerator(seed: seed, snowState: state)
    let physics = SnowPhysics.profile(for: state)
    var current = initial ?? SkierState.start(on: terrain)
    let input = SkierInput(isHolding: holding)

    for _ in 0..<frames {
        current = SkierSimulation.step(
            current, input: input, terrain: terrain, physics: physics, delta: 1.0 / 60
        )
    }
    return (current, terrain)
}

@Suite("Skier simulation")
struct SkierSimulationTests {

    @Test("the skier accelerates downhill under gravity")
    func acceleratesDownhill() {
        let start = simulate(frames: 1, holding: false, state: .packed).state
        let later = simulate(frames: 180, holding: false, state: .packed).state
        #expect(later.velocityX > start.velocityX)
        #expect(later.distanceM > 0)
    }

    @Test("the skier stays on the surface while grounded")
    func tracksTerrain() {
        let (state, terrain) = simulate(frames: 120, holding: false, state: .packed)
        if state.isGrounded {
            #expect(abs(state.altitudeM - terrain.height(at: state.distanceM)) < 0.05)
        }
    }

    @Test("speed is bounded by the surface's top speed")
    func respectsTopSpeed() {
        for snow in SnowState.allCases {
            let physics = SnowPhysics.profile(for: snow)
            let state = simulate(frames: 1_200, holding: true, state: snow).state
            // Generous headroom; the point is that it converges rather than diverging.
            #expect(state.velocityX <= 26.0 * physics.topSpeedMultiplier + 0.5)
        }
    }

    // MARK: The control decision

    @Test("tucking is faster than carving")
    func tuckingRewardsSpeed() {
        let tucked = simulate(frames: 150, holding: true, state: .powder).state
        let carved = simulate(frames: 150, holding: false, state: .powder).state
        // The entire reason to take the risk.
        #expect(tucked.velocityX > carved.velocityX)
        #expect(tucked.distanceM > carved.distanceM)
    }

    @Test("tucking builds instability, standing bleeds it off")
    func instabilityRespondsToInput() {
        let terrain = TerrainGenerator(seed: 1, snowState: .ice)
        let physics = SnowPhysics.profile(for: .ice)
        var state = SkierState.start(on: terrain)

        for _ in 0..<60 {
            state = SkierSimulation.step(
                state, input: SkierInput(isHolding: true), terrain: terrain, physics: physics, delta: 1.0 / 60
            )
        }
        let afterTuck = state.instability
        #expect(afterTuck > 0)

        for _ in 0..<60 {
            state = SkierSimulation.step(
                state, input: SkierInput(isHolding: false), terrain: terrain, physics: physics, delta: 1.0 / 60
            )
        }
        #expect(state.instability < afterTuck)
    }

    @Test("how long a tuck can be held is set by the real weather")
    func snowStateGovernsRisk() {
        /// Frames of continuous tucking before losing an edge.
        func survivalFrames(on snow: SnowState) -> Int {
            let terrain = TerrainGenerator(seed: 77, snowState: snow)
            let physics = SnowPhysics.profile(for: snow)
            var state = SkierState.start(on: terrain)

            for frame in 0..<3_600 {
                state = SkierSimulation.step(
                    state, input: SkierInput(isHolding: true), terrain: terrain, physics: physics, delta: 1.0 / 60
                )
                if state.hasCrashed { return frame }
            }
            return 3_600
        }

        // This is the design thesis expressed as an assertion: the same single input has a
        // completely different optimal usage depending on today's actual snowpack. Powder
        // forgives a permanent tuck; boilerplate punishes one within seconds.
        #expect(survivalFrames(on: .ice) < survivalFrames(on: .packed))
        #expect(survivalFrames(on: .packed) < survivalFrames(on: .powder))
        #expect(survivalFrames(on: .powder) > 600)
    }

    // MARK: Air

    @Test("holding in the air rotates the skier")
    func holdingSpinsInAir() {
        let terrain = TerrainGenerator(seed: 5, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)

        // Launch explicitly rather than hunting for a kicker, so the test measures rotation
        // and nothing else.
        let airborne = SkierState(
            distanceM: 100, altitudeM: terrain.height(at: 100) + 20,
            velocityX: 18, velocityY: 6,
            rotation: 0, angularVelocity: 0,
            isGrounded: false, hasCrashed: false,
            airTimeS: 0, totalAirTimeS: 0, flips: 0, jumpRotation: 0, instability: 0
        )

        var spinning = airborne
        for _ in 0..<30 {
            spinning = SkierSimulation.step(
                spinning, input: SkierInput(isHolding: true), terrain: terrain, physics: physics, delta: 1.0 / 60
            )
        }
        #expect(abs(spinning.jumpRotation) > 1.5)
        #expect(spinning.totalAirTimeS > 0.4)
    }

    @Test("powder absorbs a landing that crust rejects")
    func floatDecidesTheLanding() {
        /// Lands at a fixed, badly-angled attitude on the given surface.
        func lands(on snow: SnowState) -> Bool {
            let terrain = TerrainGenerator(seed: 3, snowState: snow)
            let physics = SnowPhysics.profile(for: snow)

            // Impact angle is measured against the slope being landed on, so the body
            // attitude has to be expressed relative to it. Pinning an absolute rotation
            // instead leaves the actual impact angle at the mercy of wherever the terrain
            // happens to point, which is not what this test is trying to measure.
            let badForm = 0.62
            let landingSlope = terrain.contactAngle(at: 200)

            var state = SkierState(
                distanceM: 200, altitudeM: terrain.height(at: 200) + 0.6,
                velocityX: 16, velocityY: -7,
                rotation: landingSlope + badForm, angularVelocity: 0,
                isGrounded: false, hasCrashed: false,
                airTimeS: 0.5, totalAirTimeS: 0.5, flips: 0, jumpRotation: 0, instability: 0
            )
            for _ in 0..<20 where !state.isGrounded {
                state = SkierSimulation.step(
                    state, input: SkierInput(isHolding: false), terrain: terrain, physics: physics, delta: 1.0 / 60
                )
            }
            return !state.hasCrashed
        }

        #expect(lands(on: .powder))
        #expect(!lands(on: .crust))
    }

    @Test("a crash stops the run and the skier slides out")
    func crashIsTerminal() {
        let terrain = TerrainGenerator(seed: 11, snowState: .packed)
        let physics = SnowPhysics.profile(for: .packed)
        var state = SkierState.start(on: terrain)
        state = SkierState(
            distanceM: state.distanceM, altitudeM: state.altitudeM,
            velocityX: 20, velocityY: 0, rotation: 0, angularVelocity: 0,
            isGrounded: true, hasCrashed: true,
            airTimeS: 0, totalAirTimeS: 3, flips: 1, jumpRotation: 0, instability: 1
        )

        let before = state.velocityX
        for _ in 0..<60 {
            state = SkierSimulation.step(
                state, input: SkierInput(isHolding: true), terrain: terrain, physics: physics, delta: 1.0 / 60
            )
        }
        #expect(state.hasCrashed)
        #expect(state.velocityX < before)
        // Progress and tricks earned before the crash are preserved for scoring.
        #expect(state.flips == 1)
    }

    // MARK: Determinism

    @Test("identical seed and input tape reproduce the run exactly")
    func isDeterministic() {
        /// Replays a varied tape so the result exercises both ground and air paths.
        func run() -> SkierState {
            let terrain = TerrainGenerator(seed: 909, snowState: .packed)
            let physics = SnowPhysics.profile(for: .packed)
            var state = SkierState.start(on: terrain)
            for frame in 0..<900 {
                let holding = (frame / 37) % 2 == 0
                state = SkierSimulation.step(
                    state, input: SkierInput(isHolding: holding), terrain: terrain, physics: physics, delta: 1.0 / 60
                )
            }
            return state
        }

        // The property the whole architecture leans on: ghosts are input tapes, and a
        // server can verify a leaderboard score by re-simulating rather than trusting it.
        #expect(run() == run())
    }
}

@Suite("Run scoring")
struct RunScoreTests {

    private func score(distance: Double, air: Double, flips: Int) -> RunScore {
        RunScore(
            distanceM: distance, airTimeS: air, flips: flips,
            snowState: .powder, peak: .resort, endedInCrash: false
        )
    }

    @Test("distance dominates the score")
    func distanceLeads() {
        // A bad-conditions day must remain playable rather than merely unscoreable, so
        // simply surviving a long way has to pay.
        #expect(score(distance: 3_000, air: 0, flips: 0).points > score(distance: 500, air: 6, flips: 3).points)
    }

    @Test("air and flips reward taking risk")
    func tricksAddValue() {
        let plain = score(distance: 1_000, air: 0, flips: 0)
        let stylish = score(distance: 1_000, air: 5, flips: 2)
        #expect(stylish.points > plain.points)
    }

    @Test("the share line names the conditions, not just the number")
    func shareLineCarriesConditions() {
        let line = score(distance: 4_120, air: 3, flips: 1).shareLine
        #expect(line.contains("4120m"))
        #expect(line.contains("Powder"))
        #expect(line.contains("The Resort"))
    }
}
