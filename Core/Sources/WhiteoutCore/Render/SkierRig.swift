import Foundation

/// A point on the skeleton, in skier-local units.
///
/// Deliberately not `CGPoint`: `WhiteoutCore` imports no UI framework, which is what keeps
/// the whole model testable from the command line in milliseconds.
public struct RigPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func blended(toward other: RigPoint, amount: Double) -> RigPoint {
        RigPoint(x: x + (other.x - x) * amount, y: y + (other.y - y) * amount)
    }
}

/// The skeleton at one instant.
///
/// Coordinates are normalised so that `1.0` is the skier's standing height, with the origin
/// at the point where the ski meets the snow under the boot. `+x` is downhill, `+y` is up.
/// Normalising here rather than in points means the renderer owns exactly one scale number,
/// and the pose can be reasoned about — and asserted on — without a simulator.
///
/// Stored as named joints rather than a dictionary because this is rebuilt every frame at up
/// to 120 Hz, and a per-frame dictionary allocation is a real cost for no benefit.
public struct SkierPose: Sendable, Equatable {

    public let skiTail: RigPoint
    public let skiTip: RigPoint
    public let boot: RigPoint
    public let knee: RigPoint
    public let hip: RigPoint
    public let shoulder: RigPoint
    public let elbow: RigPoint
    public let hand: RigPoint
    /// Centre of the head, not its base.
    public let head: RigPoint
    /// Far end of the pole. In profile both poles overlap, so the rig carries one.
    public let poleTip: RigPoint

    public init(
        skiTail: RigPoint,
        skiTip: RigPoint,
        boot: RigPoint,
        knee: RigPoint,
        hip: RigPoint,
        shoulder: RigPoint,
        elbow: RigPoint,
        hand: RigPoint,
        head: RigPoint,
        poleTip: RigPoint
    ) {
        self.skiTail = skiTail
        self.skiTip = skiTip
        self.boot = boot
        self.knee = knee
        self.hip = hip
        self.shoulder = shoulder
        self.elbow = elbow
        self.hand = hand
        self.head = head
        self.poleTip = poleTip
    }

    /// Height of the silhouette, crown of the head to the ski.
    public var silhouetteHeight: Double {
        head.y + SkierRig.headRadius - min(skiTail.y, skiTip.y)
    }

    /// Joint-wise interpolation. Used to cross-fade between the two canonical poses.
    ///
    /// Interpolating positions rather than angles is the right call for a two-pose rig: it
    /// cannot produce the joint flips that angle blending does when a limb crosses a
    /// quadrant, and with only two poses there is no long arc to preserve.
    public func blended(toward other: SkierPose, amount: Double) -> SkierPose {
        let t = min(max(amount, 0), 1)
        return SkierPose(
            skiTail: skiTail.blended(toward: other.skiTail, amount: t),
            skiTip: skiTip.blended(toward: other.skiTip, amount: t),
            boot: boot.blended(toward: other.boot, amount: t),
            knee: knee.blended(toward: other.knee, amount: t),
            hip: hip.blended(toward: other.hip, amount: t),
            shoulder: shoulder.blended(toward: other.shoulder, amount: t),
            elbow: elbow.blended(toward: other.elbow, amount: t),
            hand: hand.blended(toward: other.hand, amount: t),
            head: head.blended(toward: other.head, amount: t),
            poleTip: poleTip.blended(toward: other.poleTip, amount: t)
        )
    }
}

/// The skier's skeleton and the poses it can hold.
///
/// This is presentation, not physics, and it follows `FeelModel`'s precedent: a pure layer
/// that *reads* simulation state and never writes to it. Keeping it in `WhiteoutCore` rather
/// than beside the SpriteKit code buys unit tests on proportion and silhouette that would
/// otherwise need a running simulator to inspect — and a pose that a server-side replay
/// renderer could reuse unchanged.
public enum SkierRig {

    /// Ski length, in body-height units.
    ///
    /// Slightly longer than a real ski relative to its rider. The ski is the strongest read
    /// of body angle — especially in the air, where nothing else indicates which way is up —
    /// so it is worth the small liberty.
    public static let skiLength = upright.skiTip.x - upright.skiTail.x

    /// Head radius, in body-height units.
    ///
    /// A real head is about 0.065 of stature; this is a little larger so it survives at the
    /// size the skier occupies on screen. It must stay narrower than the torso, though — an
    /// earlier 0.085 made the head wider than the body and the figure read as a lollipop.
    public static let headRadius = 0.070

    /// Stroke thicknesses, in body-height units.
    ///
    /// Three classes rather than one per limb, for two reasons. Anatomically exact widths
    /// land under 1.5 points on screen at this size and turn into aliasing rather than into
    /// limbs. And the renderer draws one path per class, so three classes is three path
    /// rebuilds a frame instead of eight — which matters at 120 Hz.
    public enum Width {
        /// Torso and thighs: the body mass. Must stay wider than the head.
        public static let core = 0.175
        /// Shins and arms.
        public static let limb = 0.095
        /// Skis and poles.
        public static let equipment = 0.075
    }

    /// Segment lengths, in body-height units. One skier, so one set of bones.
    ///
    /// Poses are *built* from these rather than authored as loose joint positions, which is
    /// the only way the same limb stays the same length in every pose. Hand-placing joints
    /// looks fine per pose and silently disagrees across them: an earlier pass had an upper
    /// arm 51% shorter in the tuck than standing and a forearm 67% longer, which is what made
    /// the arms read as a blob.
    private enum Bone {
        static let shin = 0.238
        static let thigh = 0.246
        static let torso = 0.306
        static let upperArm = 0.173
        static let forearm = 0.132
        /// Shoulder to the centre of the head. Shorter than the head radius plus half the
        /// torso width, so the head always overlaps the shoulders and no neck gap opens.
        static let neck = 0.146
        static let pole = 0.715
    }

    /// Builds a pose by walking the bone chain outward from the ski.
    ///
    /// Every angle is in radians, measured from `+x` (downhill) and positive counterclockwise.
    private static func build(
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
    ) -> SkierPose {
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

    /// Standing on the edges: knees flexed, hips stacked, hands forward and out.
    ///
    /// Proportions follow a real skier closely — hip near 0.48 of stature, shoulder near
    /// 0.78, knee near 0.26 — because the upright pose is the one a player reads as "a
    /// person", and that read is what the tuck is measured against.
    public static let upright = build(
        bootRise: 0.030,
        skiRise: 0,
        shin: 1.317,
        thigh: 2.034,
        torso: 1.373,
        upperArm: -0.806,
        forearm: -0.430,
        neck: 1.293,
        pole: -2.406
    )

    /// The downhill racer's egg.
    ///
    /// This is a specific, recognisable shape rather than a crouch, and the difference is
    /// the whole reason the rig exists. Shins near vertical, hips driven back and low, back
    /// flat at roughly 18° so it reads as a single long line, forearms horizontal and thrown
    /// forward, head down between the hands. The old placeholder faked this with a 0.68
    /// vertical squash, which preserves the standing silhouette and so cannot read as a tuck
    /// at all — a tuck is a change of shape, not of height.
    public static let tuck = build(
        bootRise: 0.030,
        skiRise: 0,
        // Shin 16° off vertical, thigh driven back, back flat at 18°, forearm dead
        // horizontal, head forward and low between the hands.
        shin: 1.292,
        thigh: 2.763,
        torso: 0.314,
        upperArm: -1.047,
        forearm: 0.0,
        neck: 0.401,
        pole: 2.898
    )

    /// Airborne: legs drawn up under the body, arms out to balance.
    ///
    /// Only a mild departure from upright. The read that matters in the air is the *angle*
    /// of the skis against the horizon, which rotation already provides — an elaborate air
    /// pose competes with it rather than adding to it.
    public static let airborne = build(
        bootRise: 0.055,
        skiRise: 0.025,
        shin: 1.047,
        thigh: 2.585,
        torso: 1.317,
        upperArm: -0.900,
        forearm: 0.535,
        neck: 1.317,
        pole: -2.940,
        bootLead: 0.02
    )

    /// Collapsed: folded forward over the skis after losing it.
    ///
    /// T-102 owns the transition into this; T-101 only needs the terminal shape so a crash
    /// is not a standing skier at 55% opacity.
    public static let collapsed = build(
        bootRise: 0.030,
        skiRise: 0,
        shin: 0.644,
        thigh: 3.001,
        torso: 0.242,
        upperArm: -0.991,
        forearm: -0.401,
        neck: 0.644,
        pole: 3.092
    )

    /// The pose for one frame.
    ///
    /// Reads simulation state and cues; writes nothing. `tuckCompression` is already the
    /// normalised "how tucked are we" signal the renderer and the haptics both consume, so
    /// the rig takes it rather than re-deriving the same thing from raw input.
    public static func pose(for state: SkierState, cues: FeelCues) -> SkierPose {
        if state.hasCrashed { return collapsed }
        if !state.isGrounded { return airborne }
        return upright.blended(toward: tuck, amount: cues.tuckCompression)
    }
}
