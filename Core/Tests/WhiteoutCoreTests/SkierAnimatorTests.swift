import Testing
import Foundation
@testable import WhiteoutCore

// MARK: - Fixtures

private func state(
    grounded: Bool = true,
    crashed: Bool = false,
    distanceM: Double = 100,
    angularVelocity: Double = 0
) -> SkierState {
    SkierState(
        distanceM: distanceM, altitudeM: -30, velocityX: 18, velocityY: -5,
        rotation: -0.3, angularVelocity: angularVelocity,
        isGrounded: grounded, hasCrashed: crashed,
        airTimeS: 0, totalAirTimeS: 0, flips: 0, jumpRotation: 0,
        instability: 0.2
    )
}

private func cues(tuck: Double = 0, carve: Double = 0) -> FeelCues {
    FeelCues(
        cameraLead: 0, shake: 0, speedLines: 0,
        carveLevel: carve, windLevel: 0, tuckCompression: tuck
    )
}

/// Runs the animator forward at a fixed step, which is what the scene does with a clamped
/// delta. Returns every frame so a test can assert on the shape of the curve, not just its
/// endpoint — "it got there eventually" is exactly the assertion that let snapping through.
private func run(
    from animator: SkierAnimator = .idle,
    seconds: Double,
    delta: Double = 1.0 / 60,
    state stateFor: (Int) -> SkierState,
    cues cuesFor: (Int) -> FeelCues,
    landingImpact: (Int) -> Double = { _ in 0 }
) -> [SkierAnimator] {
    var current = animator
    var frames: [SkierAnimator] = []
    for frame in 0..<Int(seconds / delta) {
        current = current.advanced(
            for: stateFor(frame),
            cues: cuesFor(frame),
            landingImpact: landingImpact(frame),
            delta: delta
        )
        frames.append(current)
    }
    return frames
}

// MARK: - Transitions

@Suite("Skier animator — transitions")
struct SkierAnimatorTransitionTests {

    @Test("a tuck eases in over several frames rather than snapping")
    func tuckEasesIn() {
        let frames = run(seconds: 0.5, state: { _ in state() }, cues: { _ in cues(tuck: 1) })

        // The defect T-102 exists to fix: `tuckCompression` is binary, so before the animator
        // the very first frame was already fully tucked.
        #expect(frames[0].tuck < 0.25)
        #expect(frames[0].tuck > 0)
        // Committed but not instant: 90% of the way into the egg in about 0.19 s. Faster than
        // this and the head crosses four points in a single frame, which reads as a cut.
        #expect(frames[11].tuck > 0.88)
        #expect(frames.last!.tuck > 0.99)

        // Monotonic, so the pose never backs up mid-transition.
        for (previous, next) in zip(frames, frames.dropFirst()) {
            #expect(next.tuck >= previous.tuck)
        }
    }

    @Test("standing up is slower than dropping into the tuck")
    func tuckOutIsSlowerThanTuckIn() {
        let held = run(seconds: 1, state: { _ in state() }, cues: { _ in cues(tuck: 1) }).last!
        let releasing = run(from: held, seconds: 1, state: { _ in state() }, cues: { _ in cues() })

        func frameToCross(_ frames: [SkierAnimator], _ value: (SkierAnimator) -> Double) -> Int {
            frames.firstIndex { value($0) > 0.5 } ?? frames.count
        }
        let inFrames = frameToCross(
            run(seconds: 1, state: { _ in state() }, cues: { _ in cues(tuck: 1) }),
            \.tuck
        )
        let outFrames = releasing.firstIndex { $0.tuck < 0.5 } ?? releasing.count

        // The body unfolds against the wind; folding is the decisive half of the movement.
        #expect(outFrames > inFrames)
    }

    @Test("leaving the ground eases into the air pose")
    func airEasesIn() {
        let frames = run(seconds: 0.5, state: { _ in state(grounded: false) }, cues: { _ in cues() })
        #expect(frames[0].air < 0.35)
        #expect(frames.last!.air > 0.99)
    }

    @Test("the flip pose is driven by how hard the skier is actually rotating")
    func flipTracksRotation() {
        let hard = run(
            seconds: 1,
            state: { _ in state(grounded: false, angularVelocity: -4.4) },
            cues: { _ in cues() }
        ).last!
        let loose = run(
            seconds: 1,
            state: { _ in state(grounded: false, angularVelocity: -1.1) },
            cues: { _ in cues() }
        ).last!
        let floated = run(
            seconds: 1,
            state: { _ in state(grounded: false, angularVelocity: 0) },
            cues: { _ in cues() }
        ).last!

        // A committed backflip balls up; a floated jump stays open. Without this the two
        // are the same drawing rotated, and the rotation carries the whole read alone.
        #expect(hard.flip > 0.98)
        #expect(abs(loose.flip - 0.25) < 0.05)
        #expect(floated.flip < 0.01)
    }

    @Test("a flip unwinds once the skier is back on the snow")
    func flipReleasesOnLanding() {
        let spinning = run(
            seconds: 1,
            state: { _ in state(grounded: false, angularVelocity: -4.4) },
            cues: { _ in cues() }
        ).last!
        let landed = run(from: spinning, seconds: 1, state: { _ in state() }, cues: { _ in cues() })
        #expect(landed.last!.flip < 0.01)
        #expect(landed.last!.air < 0.01)
    }

    @Test("a landing fires as an impulse and springs back")
    func landingIsAnImpulse() {
        let frames = run(
            seconds: 1,
            state: { _ in state() },
            cues: { _ in cues() },
            landingImpact: { $0 == 0 ? 0.8 : 0 }
        )
        // Full depth on the frame the impact is reported — absorption cannot lag the thing
        // it is absorbing.
        #expect(abs(frames[0].landing - 0.8) < 1e-9)
        // Then springs back over roughly a third of a second.
        #expect(frames[20].landing < 0.4)
        #expect(frames.last!.landing < 0.01)
    }

    @Test("a harder landing mid-recovery overrides the softer one rather than summing")
    func landingsDoNotStack() {
        let frames = run(
            seconds: 1,
            state: { _ in state() },
            cues: { _ in cues() },
            landingImpact: { frame in
                if frame == 0 { return 0.5 }
                if frame == 6 { return 0.9 }
                return 0
            }
        )
        #expect(abs(frames[6].landing - 0.9) < 1e-9)

        // A softer second impact cannot deepen an absorption already deeper than it, so the
        // run containing it must be indistinguishable from the run without it. Asserting a
        // threshold instead would have passed for the wrong reason: two frames of decay
        // already put the value at 0.70, well above the 0.2 being ignored.
        func withSecondImpact(_ second: Double) -> [SkierAnimator] {
            run(
                seconds: 1,
                state: { _ in state() },
                cues: { _ in cues() },
                landingImpact: { frame in
                    if frame == 0 { return 0.9 }
                    if frame == 2 { return second }
                    return 0
                }
            )
        }
        for (soft, none) in zip(withSecondImpact(0.2), withSecondImpact(0)) {
            #expect(soft.landing == none.landing)
        }
    }

    @Test("a crash collapses over time instead of cutting to the sprawl")
    func crashEasesIn() {
        let frames = run(
            seconds: 0.6,
            state: { _ in state(crashed: true) },
            cues: { _ in cues() }
        )
        #expect(frames[0].crash < 0.3)
        #expect(frames.last!.crash > 0.99)
        for (previous, next) in zip(frames, frames.dropFirst()) {
            #expect(next.crash >= previous.crash)
        }
    }

    @Test("every weight is frame-rate independent")
    func easingIsFrameRateIndependent() {
        // A 120 Hz phone and a 60 Hz one must animate the same tuck, or the game feels
        // different on different hardware for reasons no player could name.
        let at60 = run(seconds: 0.25, delta: 1.0 / 60, state: { _ in state() }, cues: { _ in cues(tuck: 1) }).last!
        let at120 = run(seconds: 0.25, delta: 1.0 / 120, state: { _ in state() }, cues: { _ in cues(tuck: 1) }).last!
        #expect(abs(at60.tuck - at120.tuck) < 0.01)

        let crash60 = run(seconds: 0.25, delta: 1.0 / 60, state: { _ in state(crashed: true) }, cues: { _ in cues() }).last!
        let crash120 = run(seconds: 0.25, delta: 1.0 / 120, state: { _ in state(crashed: true) }, cues: { _ in cues() }).last!
        #expect(abs(crash60.crash - crash120.crash) < 0.01)
    }

    @Test("weights never leave 0...1, whatever the simulation reports")
    func weightsStayNormalised() {
        let frames = run(
            seconds: 2,
            state: { frame in
                state(
                    grounded: frame % 7 < 3,
                    crashed: frame > 90,
                    distanceM: Double(frame) * 0.4,
                    angularVelocity: frame % 5 == 0 ? -22 : 0
                )
            },
            cues: { frame in cues(tuck: frame % 3 == 0 ? 1 : 0, carve: 0.7) },
            landingImpact: { $0 % 11 == 0 ? 1.0 : 0 }
        )
        for animator in frames {
            for weight in [animator.tuck, animator.air, animator.flip, animator.landing, animator.crash] {
                #expect(weight >= 0 && weight <= 1)
            }
        }
    }
}

// MARK: - Composition

@Suite("Skier animator — pose composition")
struct SkierAnimatorCompositionTests {

    @Test("bones stay rigid through every composed pose, not just every authored one")
    func composedPosesAreRigid() {
        // The composition stacks up to five blends before solving. This is the assertion
        // that the stack cannot contract a bone at any depth.
        let reference = boneLengths(SkierRig.upright)
        let frames = run(
            seconds: 3,
            state: { frame in
                state(
                    grounded: frame % 9 < 5,
                    crashed: frame > 150,
                    distanceM: Double(frame) * 0.35,
                    angularVelocity: frame % 4 == 0 ? -4.4 : -1.2
                )
            },
            cues: { frame in cues(tuck: frame % 6 < 3 ? 1 : 0, carve: 0.8) },
            landingImpact: { $0 % 13 == 0 ? 0.7 : 0 }
        )

        for (frame, animator) in frames.enumerated() {
            let pose = animator.pose(
                for: state(distanceM: Double(frame) * 0.35),
                cues: cues(carve: 0.8)
            )
            for (bone, length) in boneLengths(pose) {
                #expect(abs(length - (reference[bone] ?? 0)) < 1e-9, "frame \(frame): \(bone)")
            }
        }
    }

    @Test("an idle animator on a fresh run draws a standing skier")
    func idleIsUpright() {
        let start = SkierState.start(on: TerrainGenerator(seed: 1, snowState: .packed))
        #expect(SkierAnimator.idle.pose(for: start, cues: .idle) == SkierRig.upright)
    }

    @Test("a fully committed tuck reaches the tuck pose")
    func settledTuckMatches() {
        let settled = run(seconds: 2, state: { _ in state() }, cues: { _ in cues(tuck: 1) }).last!
        let pose = settled.pose(for: state(), cues: cues(tuck: 1))
        // Not exact equality: the weight approaches 1 asymptotically and never lands on it.
        #expect(abs(pose.silhouetteHeight - SkierRig.tuck.silhouetteHeight) < 0.002)
    }

    @Test("a settled crash reaches the collapsed pose whatever preceded it")
    func settledCrashMatches() {
        for preceding in [state(), state(grounded: false, angularVelocity: -4.4)] {
            let mid = run(seconds: 1, state: { _ in preceding }, cues: { _ in cues(tuck: 1) }).last!
            let settled = run(
                from: mid, seconds: 2,
                state: { _ in state(crashed: true) }, cues: { _ in cues() }
            ).last!
            let pose = settled.pose(for: state(crashed: true), cues: cues())
            #expect(abs(pose.silhouetteHeight - SkierRig.collapsed.silhouetteHeight) < 0.002)
        }
    }

    @Test("the carve rhythm is driven by distance, so it scales with speed for free")
    func carveIsDistanceDriven() {
        let animator = SkierAnimator.idle
        let carving = cues(carve: 1)

        // Same distance, same pose — no hidden clock. This is also what keeps a replay
        // identical at any frame rate.
        let a = animator.pose(for: state(distanceM: 42), cues: carving)
        let b = animator.pose(for: state(distanceM: 42), cues: carving)
        #expect(a == b)

        // Half a wavelength apart is the opposite end of the flex/extend cycle.
        let low = animator.pose(for: state(distanceM: 17.0 * 0.75), cues: carving)
        let high = animator.pose(for: state(distanceM: 17.0 * 0.25), cues: carving)
        #expect(high.silhouetteHeight > low.silhouetteHeight + 0.05)
    }

    @Test("the carve rhythm fades out when there is no grip or no speed to carve with")
    func carveFadesWithCarveLevel() {
        let animator = SkierAnimator.idle
        // `carveLevel` already encodes grounded, not-tucking, not-crashed, speed and grip,
        // so a stationary skier on ice stands still rather than swaying on the spot.
        let still = animator.pose(for: state(distanceM: 17.0 * 0.25), cues: cues(carve: 0))
        #expect(still == SkierRig.upright)
    }

    @Test("a crash overrides whatever the legs were doing")
    func crashWins() {
        // Tucked, airborne, mid-flip and landing all at once, then crashed.
        let chaos = run(
            seconds: 1,
            state: { _ in state(grounded: false, angularVelocity: -4.4) },
            cues: { _ in cues(tuck: 1) },
            landingImpact: { $0 == 0 ? 1 : 0 }
        ).last!
        let settled = run(
            from: chaos, seconds: 2,
            state: { _ in state(crashed: true) }, cues: { _ in cues() }
        ).last!
        let pose = settled.pose(for: state(crashed: true), cues: cues())
        #expect(abs(pose.silhouetteHeight - SkierRig.collapsed.silhouetteHeight) < 0.002)
    }
}
