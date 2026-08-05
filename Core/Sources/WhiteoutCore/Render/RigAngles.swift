import Foundation

/// The skeleton as joint *angles*, which is the form every pose is authored and blended in.
///
/// This is the canonical representation; `SkierPose` is what falls out of solving it. The
/// direction of that dependency is the whole of T-111. Blending two sets of joint positions
/// moves each joint along a straight chord, and a chord is shorter than the arc the joint
/// actually travels — so every bone contracts at intermediate `t` and springs back at the
/// ends. Blending angles and re-solving cannot do that: bone lengths are constants of the
/// solver, so they are rigid at every `t` by construction rather than by tolerance.
///
/// Every angle is in radians, measured from `+x` (downhill) and positive counterclockwise.
public struct RigAngles: Sendable, Equatable {

    /// Height of the boot above the snow.
    public let bootRise: Double
    /// Tilt of the ski, and how far the tip lifts.
    public let skiRise: Double
    /// Downhill offset of the boot from the rig origin.
    public let bootLead: Double

    public let shin: Double
    public let thigh: Double
    public let torso: Double
    public let upperArm: Double
    public let forearm: Double
    public let neck: Double
    public let pole: Double

    public init(
        bootRise: Double,
        skiRise: Double,
        shin: Double,
        thigh: Double,
        torso: Double,
        upperArm: Double,
        forearm: Double,
        neck: Double,
        pole: Double,
        bootLead: Double = 0
    ) {
        self.bootRise = bootRise
        self.skiRise = skiRise
        self.bootLead = bootLead
        self.shin = shin
        self.thigh = thigh
        self.torso = torso
        self.upperArm = upperArm
        self.forearm = forearm
        self.neck = neck
        self.pole = pole
    }

    /// Segment lengths, in body-height units. One skier, so one set of bones.
    ///
    /// Poses are *built* from these rather than authored as loose joint positions, which is
    /// the only way the same limb stays the same length in every pose. Hand-placing joints
    /// looks fine per pose and silently disagrees across them: an earlier pass had an upper
    /// arm 51% shorter in the tuck than standing and a forearm 67% longer, which is what made
    /// the arms read as a blob.
    public enum Bone {
        public static let shin = 0.238
        public static let thigh = 0.246
        public static let torso = 0.306
        public static let upperArm = 0.173
        public static let forearm = 0.132
        /// Shoulder to the centre of the head. Shorter than the head radius plus half the
        /// torso width, so the head always overlaps the shoulders and no neck gap opens.
        public static let neck = 0.146
        public static let pole = 0.715
    }

    /// Walks the bone chain outward from the ski to produce drawable joint positions.
    public func solved() -> SkierPose {
        func step(_ from: RigPoint, _ angle: Double, _ length: Double) -> RigPoint {
            RigPoint(x: from.x + cos(angle) * length, y: from.y + sin(angle) * length)
        }

        let boot = RigPoint(x: bootLead, y: bootRise)
        let knee = step(boot, shin, Bone.shin)
        let hip = step(knee, thigh, Bone.thigh)
        let shoulder = step(hip, torso, Bone.torso)
        let elbow = step(shoulder, upperArm, Bone.upperArm)
        let hand = step(elbow, forearm, Bone.forearm)

        return SkierPose(
            skiTail: RigPoint(x: -0.50, y: skiRise * -0.02),
            skiTip: RigPoint(x: 0.65, y: 0.045 + skiRise),
            boot: boot,
            knee: knee,
            hip: hip,
            shoulder: shoulder,
            elbow: elbow,
            hand: hand,
            head: step(shoulder, neck, Bone.neck),
            poleTip: step(hand, pole, Bone.pole)
        )
    }

    /// Interpolates toward another pose, taking the short way round every joint.
    ///
    /// Shortest-arc rather than a plain lerp, and the pole is why. Standing, it sits at
    /// −2.406 rad; tucked, at +2.898. Those describe nearly the same direction — the pole
    /// trails behind the skier in both — but they are 5.3 rad apart numerically, so a plain
    /// lerp sweeps the pole the long way, forward *through* the skier's body, and back. Taking
    /// the −0.98 rad short arc instead swings it the way an actual pole swings.
    ///
    /// The joint-flip hazard that argued for position blending in the first place is real in
    /// general and absent here: it needs a bone whose authored angles are a half-turn or more
    /// apart, so that "the short way" becomes ambiguous and then picks the wrong side. The
    /// widest separation in this rig is the pole between `carveRight` and `flipTuck`, at 1.49
    /// rad — 1.65 rad of headroom below π. `RigAnglesTests` asserts that margin, so a future
    /// pose cannot quietly spend it.
    public func blended(toward other: RigAngles, amount: Double) -> RigAngles {
        let t = min(max(amount, 0), 1)
        guard t > 0 else { return self }
        guard t < 1 else { return other }

        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func arc(_ a: Double, _ b: Double) -> Double { a + Self.shortestArc(from: a, to: b) * t }

        return RigAngles(
            // Offsets, not angles: these are lengths along an axis and interpolate linearly.
            bootRise: lerp(bootRise, other.bootRise),
            skiRise: lerp(skiRise, other.skiRise),
            shin: arc(shin, other.shin),
            thigh: arc(thigh, other.thigh),
            torso: arc(torso, other.torso),
            upperArm: arc(upperArm, other.upperArm),
            forearm: arc(forearm, other.forearm),
            neck: arc(neck, other.neck),
            pole: arc(pole, other.pole),
            bootLead: lerp(bootLead, other.bootLead)
        )
    }

    /// Signed rotation from `a` to `b`, wrapped into `-π...π`.
    static func shortestArc(from a: Double, to b: Double) -> Double {
        var delta = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }
}
