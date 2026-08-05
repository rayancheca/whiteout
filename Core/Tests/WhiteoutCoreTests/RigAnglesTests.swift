import Testing
import Foundation
@testable import WhiteoutCore

/// Bone lengths measured off a solved pose, so a change to the solver cannot pass unnoticed.
func boneLengths(_ pose: SkierPose) -> [String: Double] {
    [
        "shin": hypot(pose.knee.x - pose.boot.x, pose.knee.y - pose.boot.y),
        "thigh": hypot(pose.hip.x - pose.knee.x, pose.hip.y - pose.knee.y),
        "torso": hypot(pose.shoulder.x - pose.hip.x, pose.shoulder.y - pose.hip.y),
        "upperArm": hypot(pose.elbow.x - pose.shoulder.x, pose.elbow.y - pose.shoulder.y),
        "forearm": hypot(pose.hand.x - pose.elbow.x, pose.hand.y - pose.elbow.y),
        "neck": hypot(pose.head.x - pose.shoulder.x, pose.head.y - pose.shoulder.y),
        "pole": hypot(pose.poleTip.x - pose.hand.x, pose.poleTip.y - pose.hand.y),
        "ski": pose.skiTip.x - pose.skiTail.x
    ]
}

/// Every ordered pair of authored poses. Blending is not symmetric in general, so both
/// directions are worth walking.
private func posePairs() -> [(String, RigAngles, RigAngles)] {
    var pairs: [(String, RigAngles, RigAngles)] = []
    for from in SkierRig.allAngles {
        for to in SkierRig.allAngles where from.name != to.name {
            pairs.append(("\(from.name)→\(to.name)", from.angles, to.angles))
        }
    }
    return pairs
}

/// Sampled finely enough to catch a contraction that only appears near one end.
private let blendSamples = stride(from: 0.0, through: 1.0, by: 0.02).map { $0 }

// MARK: - T-111

@Suite("Rig angles — rigidity under blending")
struct RigAnglesRigidityTests {

    @Test("bones keep their length at every point of every transition")
    func bonesAreRigidMidBlend() {
        // The whole of T-111. The suite this replaces only ever measured the *authored*
        // poses, which are rigid by construction under any blending scheme — so it passed
        // while position blending contracted every bone in between, worst at t = 0.5, and
        // sprang it back at both ends where the assertions happened to look.
        let reference = boneLengths(SkierRig.upright)

        for (name, from, to) in posePairs() {
            for t in blendSamples {
                let pose = from.blended(toward: to, amount: t).solved()
                for (bone, length) in boneLengths(pose) {
                    let expected = reference[bone] ?? 0
                    #expect(
                        abs(length - expected) < 1e-9,
                        "\(name) at t=\(t): \(bone) is \(length), standing is \(expected)"
                    )
                }
            }
        }
    }

    @Test("position blending would have failed this, which is why it is gone")
    func positionBlendingContractsBones() {
        // Kept as the regression's own headstone. If someone reintroduces joint-position
        // interpolation, this documents the exact magnitude of what it costs.
        let a = SkierRig.upright
        let b = SkierRig.tuck
        func lerp(_ p: RigPoint, _ q: RigPoint, _ t: Double) -> RigPoint {
            RigPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
        }

        let hip = lerp(a.hip, b.hip, 0.5)
        let shoulder = lerp(a.shoulder, b.shoulder, 0.5)
        let torso = hypot(shoulder.x - hip.x, shoulder.y - hip.y)

        // The torso is 0.306 long in both poses and would be 0.28 at the midpoint — a 9%
        // contraction, on the longest bone in the body, every time the player tucks.
        #expect(torso < RigAngles.Bone.torso - 0.02)
    }
}

// MARK: - Shortest arc

@Suite("Rig angles — shortest-arc interpolation")
struct RigAnglesArcTests {

    @Test("the pole takes the short way round rather than sweeping through the body")
    func poleTakesTheShortArc() {
        // Standing, the pole sits at -2.406 rad; tucked, at +2.898. Both trail behind the
        // skier, but a plain lerp reads them as 5.3 rad apart and swings the pole forward
        // through the skier's chest to get between them.
        let mid = SkierRig.uprightAngles.blended(toward: SkierRig.tuckAngles, amount: 0.5)
        let plainLerp = (SkierRig.uprightAngles.pole + SkierRig.tuckAngles.pole) / 2

        // The short arc stays behind the skier; the plain lerp lands in front of them.
        #expect(cos(mid.pole) < 0)
        #expect(cos(plainLerp) > 0)

        let pose = mid.solved()
        #expect(pose.poleTip.x < pose.hand.x)
    }

    @Test("the pole tip never crosses in front of the hand mid-tuck")
    func poleStaysBehindThroughout() {
        for t in blendSamples {
            let pose = SkierRig.uprightAngles
                .blended(toward: SkierRig.tuckAngles, amount: t)
                .solved()
            #expect(pose.poleTip.x < pose.hand.x, "pole swung forward at t=\(t)")
        }
    }

    @Test("no authored pair is close enough to a half-turn for the short way to be ambiguous")
    func arcsStayClearOfPi() {
        // Shortest-arc interpolation picks the wrong side once a bone's endpoints reach π
        // apart. Nothing in the rig is near that today; this fails the moment a new pose
        // spends the margin, which is the only way that failure would ever be noticed.
        let bones: [(name: String, path: KeyPath<RigAngles, Double>)] = [
            ("shin", \.shin), ("thigh", \.thigh), ("torso", \.torso),
            ("upperArm", \.upperArm), ("forearm", \.forearm),
            ("neck", \.neck), ("pole", \.pole)
        ]

        for (name, path) in bones {
            for from in SkierRig.allAngles {
                for to in SkierRig.allAngles where from.name != to.name {
                    let arc = abs(RigAngles.shortestArc(
                        from: from.angles[keyPath: path],
                        to: to.angles[keyPath: path]
                    ))
                    #expect(
                        arc < .pi - 1.0,
                        "\(name) spans \(arc) rad between \(from.name) and \(to.name)"
                    )
                }
            }
        }
    }

    @Test("shortest arc wraps in both directions and is antisymmetric")
    func shortestArcWraps() {
        #expect(abs(RigAngles.shortestArc(from: 0.1, to: 0.4) - 0.3) < 1e-12)
        // Across the ±π seam: 0.2 rad apart, not 6.08.
        #expect(abs(RigAngles.shortestArc(from: 3.0, to: -3.0) - 0.283185) < 1e-5)
        #expect(abs(RigAngles.shortestArc(from: -3.0, to: 3.0) + 0.283185) < 1e-5)
        // A full turn is no rotation at all.
        #expect(abs(RigAngles.shortestArc(from: 0.5, to: 0.5 + 2 * .pi)) < 1e-12)
    }
}

// MARK: - Blend contract

@Suite("Rig angles — blend contract")
struct RigAnglesBlendTests {

    @Test("the ends of a blend are the authored poses exactly")
    func endpointsAreExact() {
        for (name, from, to) in posePairs() {
            #expect(from.blended(toward: to, amount: 0) == from, "\(name)")
            #expect(from.blended(toward: to, amount: 1) == to, "\(name)")
        }
    }

    @Test("blending is clamped, so an out-of-range weight cannot break the pose")
    func blendIsClamped() {
        let a = SkierRig.uprightAngles
        let b = SkierRig.tuckAngles
        #expect(a.blended(toward: b, amount: 3) == b)
        #expect(a.blended(toward: b, amount: -2) == a)
        #expect(a.blended(toward: b, amount: .infinity) == b)
    }

    @Test("every authored pose keeps the skeleton anatomically ordered")
    func authoredPosesAreOrdered() {
        for (name, angles) in SkierRig.allAngles {
            let pose = angles.solved()
            // The skis are the strongest read of body angle, so they must stay the longest
            // element and must not creep above the knee.
            #expect(pose.skiTip.x - pose.skiTail.x > 1.0, "\(name)")
            #expect(pose.skiTail.x < pose.boot.x, "\(name)")
            #expect(pose.skiTip.x > pose.boot.x, "\(name)")
            #expect(pose.skiTip.y < pose.knee.y, "\(name)")

            // Head radius plus half the torso width has to exceed the neck bone, or the
            // figure comes apart at the collar in whichever pose gets it wrong.
            let reach = SkierRig.headRadius + SkierRig.Width.core / 2
            let neck = hypot(pose.head.x - pose.shoulder.x, pose.head.y - pose.shoulder.y)
            #expect(neck < reach, "\(name)")
        }
    }

    @Test("the skeleton stays ordered mid-transition too, not only at the ends")
    func blendedPosesAreOrdered() {
        let reach = SkierRig.headRadius + SkierRig.Width.core / 2
        for (name, from, to) in posePairs() {
            for t in blendSamples {
                let pose = from.blended(toward: to, amount: t).solved()
                #expect(pose.skiTip.y < pose.knee.y, "\(name) at t=\(t)")
                #expect(pose.head.y > pose.shoulder.y, "\(name) at t=\(t)")
                let neck = hypot(pose.head.x - pose.shoulder.x, pose.head.y - pose.shoulder.y)
                #expect(neck < reach, "\(name) at t=\(t)")
            }
        }
    }
}
