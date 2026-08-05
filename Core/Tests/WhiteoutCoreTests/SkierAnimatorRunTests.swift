import Testing
import Foundation
@testable import WhiteoutCore

/// One frame of a headless run: the real simulation, the real cues, the real animator.
private struct Frame {
    let state: SkierState
    let cues: FeelCues
    let animator: SkierAnimator
    let pose: SkierPose
}

/// Drives an actual run rather than synthesising states.
///
/// The transition suite feeds the animator hand-built `SkierState`s, which is the right way
/// to pin one behaviour at a time but cannot prove the combinations a real descent produces —
/// a landing that arrives mid-flip, a crash that lands on the frame the skier touches down.
/// This walks the genuine simulation over generated terrain instead, so those overlaps happen
/// on their own. It is deterministic from the seed, so it is a fixed sequence, not a fuzz run.
private func descend(
    seed: UInt64,
    snowState: SnowState,
    isHolding: @escaping (Int) -> Bool,
    frames frameCount: Int = 1_800,
    delta: Double = 1.0 / 60
) -> [Frame] {
    let terrain = TerrainGenerator(seed: seed, snowState: snowState)
    let physics = SnowPhysics.profile(for: snowState)
    let weather = MountainWeather(
        elevationM: 2_400, temperatureC: -6, freshSnowCm: 5, snowfallCmPerHour: 0,
        isRainingAtAltitude: false, windSpeedKmh: 12, windGustKmh: 18,
        windDirectionDeg: 280, visibilityM: 15_000, cloudCoverPercent: 40,
        sunAltitudeDeg: 30, localHour: 11, maxTemperature24hC: -3, minTemperature24hC: -11
    )

    var state = SkierState.start(on: terrain)
    var animator = SkierAnimator.idle
    var result: [Frame] = []

    for frame in 0..<frameCount {
        let holding = isHolding(frame)
        let previous = state
        state = SkierSimulation.step(
            state,
            input: SkierInput(isHolding: holding),
            terrain: terrain,
            physics: physics,
            delta: delta
        )
        let cues = FeelModel.cues(for: state, physics: physics, weather: weather, isTucking: holding)
        let impact = FeelModel.landingImpact(previous: previous, current: state)
        animator = animator.advanced(for: state, cues: cues, landingImpact: impact, delta: delta)
        result.append(
            Frame(state: state, cues: cues, animator: animator, pose: animator.pose(for: state, cues: cues))
        )
    }
    return result
}

@Suite("Skier animator — over a real run")
struct SkierAnimatorRunTests {

    /// Held throughout: fastest, most airborne, and ends in a crash on every surface.
    private func heldRun(seed: UInt64, snow: SnowState = .packed) -> [Frame] {
        descend(seed: seed, snowState: snow, isHolding: { _ in true })
    }

    @Test("a held descent actually reaches air, rotation, landing and a crash")
    func theRunExercisesEveryState() {
        // Guards the suite below: if the terrain stopped producing jumps, the rigidity and
        // ordering assertions would still pass while silently covering nothing but a glide.
        let frames = heldRun(seed: 17)

        #expect(frames.contains { !$0.state.isGrounded })
        #expect(frames.contains { $0.animator.air > 0.9 })
        #expect(frames.contains { $0.animator.flip > 0.9 })
        #expect(frames.contains { $0.animator.landing > 0.1 })
        #expect(frames.contains { $0.state.hasCrashed })
        #expect(frames.contains { $0.animator.crash > 0.99 })
        #expect(frames.contains { $0.animator.tuck > 0.99 })
    }

    @Test("bones stay rigid for every frame of a real descent", arguments: [
        SnowState.powder, .packed, .crust, .ice, .slush, .windSlab
    ])
    func bonesStayRigidAcrossARun(snow: SnowState) {
        let reference = boneLengths(SkierRig.upright)
        // Alternating input crosses every boundary the composed pose has: tucking into a
        // takeoff, releasing mid-flip, standing up on touchdown.
        let frames = descend(seed: 4_242, snowState: snow, isHolding: { $0 % 47 < 31 })

        for (index, frame) in frames.enumerated() {
            for (bone, length) in boneLengths(frame.pose) {
                #expect(
                    abs(length - (reference[bone] ?? 0)) < 1e-9,
                    "\(snow) frame \(index): \(bone) is \(length)"
                )
            }
        }
    }

    @Test("the skeleton never comes apart during a real descent")
    func skeletonStaysWholeAcrossARun() {
        let reach = SkierRig.headRadius + SkierRig.Width.core / 2
        let frames = descend(seed: 90_210, snowState: .crust, isHolding: { $0 % 31 < 19 })

        for (index, frame) in frames.enumerated() {
            let pose = frame.pose
            #expect(pose.head.y > pose.shoulder.y, "frame \(index)")
            #expect(pose.skiTip.y < pose.knee.y, "frame \(index)")
            #expect(pose.skiTip.x > pose.boot.x, "frame \(index)")
            let neck = hypot(pose.head.x - pose.shoulder.x, pose.head.y - pose.shoulder.y)
            #expect(neck < reach, "frame \(index)")
            // The pole trails the hand in every authored pose; shortest-arc blending is what
            // keeps that true in between, and a real run is where it would show if it were not.
            #expect(pose.poleTip.x < pose.hand.x, "frame \(index)")
        }
    }

    private static func joints(_ pose: SkierPose) -> [(String, RigPoint)] {
        [
            ("boot", pose.boot), ("knee", pose.knee), ("hip", pose.hip),
            ("shoulder", pose.shoulder), ("elbow", pose.elbow), ("hand", pose.hand),
            ("head", pose.head), ("poleTip", pose.poleTip)
        ]
    }

    /// Per-frame travel budget, in body-height units, per joint.
    ///
    /// One global number would be wrong in both directions. A bone chain accumulates every
    /// rotation upstream of a joint, so the pole tip legitimately travels six times as far as
    /// the boot on the same frame; a threshold loose enough for the tip would let the boot
    /// teleport unnoticed. Each of these sits about 1.35× the worst case measured across five
    /// runs on five surfaces, so every joint is tight where it can be — and
    /// `easingBeatsAHardSwitch` proves each is still well under a single-frame switch.
    private static let travelBudget: [String: Double] = [
        "boot": 0.032, "knee": 0.04, "hip": 0.07, "shoulder": 0.135,
        "elbow": 0.14, "hand": 0.15, "head": 0.18, "poleTip": 0.22
    ]

    @Test("no joint jumps between consecutive frames of a real descent")
    func poseIsContinuous() {
        // The defect T-102 exists to remove: the old rig switched pose outright on a state
        // change, so takeoff, touchdown and the crash each moved every joint at once in a
        // single frame.
        let frames = descend(seed: 17, snowState: .packed, isHolding: { $0 % 53 < 37 })

        for (index, pair) in zip(frames, frames.dropFirst()).enumerated() {
            for ((name, a), (_, b)) in zip(Self.joints(pair.0.pose), Self.joints(pair.1.pose)) {
                let travel = hypot(b.x - a.x, b.y - a.y)
                #expect(
                    travel < (Self.travelBudget[name] ?? 0),
                    "frame \(index)→\(index + 1): \(name) moved \(travel)"
                )
            }
        }
    }

    @Test("the eased transition moves a joint far less than the hard switch it replaced")
    func easingBeatsAHardSwitch() {
        // The budgets above are calibrated against current behaviour, which on its own would
        // only ever detect *change*. This is the assertion with an independent reference: the
        // worst single-frame switch the old rig could make, which is the largest distance any
        // joint spans between two authored poses. Measuring only upright→tuck would not do —
        // that pair happens to leave the boot exactly where it was.
        var worstSnap: [String: Double] = [:]
        for from in SkierRig.allAngles {
            for to in SkierRig.allAngles where from.name != to.name {
                for ((name, a), (_, b)) in zip(
                    Self.joints(from.angles.solved()),
                    Self.joints(to.angles.solved())
                ) {
                    worstSnap[name] = max(worstSnap[name] ?? 0, hypot(b.x - a.x, b.y - a.y))
                }
            }
        }

        for (name, budget) in Self.travelBudget {
            let snapped = worstSnap[name] ?? 0
            // Every joint is held to under half of what a single-frame switch would move it.
            #expect(budget < snapped * 0.5, "\(name): budget \(budget) vs snap \(snapped)")
        }
    }

    @Test("a run is reproducible frame for frame from its seed")
    func runsAreDeterministic() {
        // The animator sits in the feel layer and must not have introduced any ambient state
        // that would break replay — the property the whole anti-cheat design rests on.
        let a = heldRun(seed: 777)
        let b = heldRun(seed: 777)
        #expect(a.count == b.count)
        for (x, y) in zip(a, b) {
            #expect(x.state == y.state)
            #expect(x.animator == y.animator)
            #expect(x.pose == y.pose)
        }
    }
}
