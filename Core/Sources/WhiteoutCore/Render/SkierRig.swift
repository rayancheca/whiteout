import Foundation

/// The skier's skeleton and the poses it can hold.
///
/// This is presentation, not physics, and it follows `FeelModel`'s precedent: a pure layer
/// that *reads* simulation state and never writes to it. Keeping it in `WhiteoutCore` rather
/// than beside the SpriteKit code buys unit tests on proportion and silhouette that would
/// otherwise need a running simulator to inspect — and a pose that a server-side replay
/// renderer could reuse unchanged.
///
/// Every pose here is a `RigAngles`. Solving one is cheap — six sin/cos pairs — so the
/// renderer blends angles all the way down and solves exactly once per frame.
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

    // MARK: - Authored poses

    /// Standing on the edges: knees flexed, hips stacked, hands forward and out.
    ///
    /// Proportions follow a real skier closely — hip near 0.48 of stature, shoulder near
    /// 0.78, knee near 0.26 — because the upright pose is the one a player reads as "a
    /// person", and that read is what every other pose is measured against.
    public static let uprightAngles = RigAngles(
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
    public static let tuckAngles = RigAngles(
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

    /// The flexed half of an edge change: weight on, body low, inside hand dropping.
    ///
    /// Left and right are named for the turn, but what a *profile* view can actually show of
    /// an edge change is flexion against extension plus the swing of the pole hand — the
    /// lateral half of the movement is the half pointing at the camera. So the pair is
    /// authored as the two ends of that visible arc rather than as a mirrored L and R, which
    /// in profile would be very nearly the same drawing twice.
    public static let carveLeftAngles = RigAngles(
        bootRise: 0.022,
        skiRise: 0,
        shin: 1.190,
        thigh: 2.290,
        torso: 1.240,
        upperArm: -0.640,
        forearm: -0.240,
        neck: 1.220,
        pole: -2.640
    )

    /// The extended half: rising off the old edge, hand coming up and back.
    ///
    /// The pair spans 10% of standing height, which sounds like a lot for a bob and is not:
    /// at a 30-point body that is 3 points. The swing that actually sells the rhythm is the
    /// pole — 0.45 rad across a 0.715-unit lever moves the tip about 10 points, three times
    /// the body's own travel. A first pass at half these amplitudes measured fine and was
    /// invisible on screen.
    public static let carveRightAngles = RigAngles(
        bootRise: 0.038,
        skiRise: 0,
        shin: 1.395,
        thigh: 1.870,
        torso: 1.455,
        upperArm: -0.930,
        forearm: -0.590,
        neck: 1.345,
        pole: -2.190
    )

    /// Airborne: legs drawn up under the body, arms out to balance.
    ///
    /// Only a mild departure from upright. The read that matters in the air is the *angle*
    /// of the skis against the horizon, which rotation already provides — an elaborate air
    /// pose competes with it rather than adding to it.
    public static let airborneAngles = RigAngles(
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

    /// Mid-rotation: knees pulled to the chest, torso folded, hand reaching for the ski.
    ///
    /// Blended in by how hard the skier is actually spinning rather than applied whenever
    /// airborne, so a floated jump stays open and a backflip balls up. Compacting the body
    /// is also what sells the rotation: a rigid figure rotating about its own centre reads
    /// as a turning sprite, while one that draws itself in reads as a person committing.
    public static let flipTuckAngles = RigAngles(
        bootRise: 0.082,
        skiRise: 0.030,
        shin: 0.790,
        thigh: 2.985,
        torso: 0.845,
        upperArm: -1.244,
        forearm: -0.898,
        neck: 0.795,
        pole: 2.604,
        bootLead: 0.050
    )

    /// Absorbing an impact: deep flex through the legs, chest forward, arms up for balance.
    ///
    /// Fired as a decaying impulse on touchdown, not as a held state. Landing is the one
    /// moment the whole run's speed becomes a force the body has to eat, and without this
    /// the skier arrives from a backflip already standing, which reads as the ground being
    /// soft rather than as the skier being good.
    public static let landingAngles = RigAngles(
        bootRise: 0.026,
        skiRise: 0,
        shin: 1.180,
        thigh: 2.610,
        torso: 0.930,
        upperArm: -0.450,
        forearm: 0.190,
        neck: 1.010,
        pole: -2.740
    )

    /// Collapsed: folded forward over the skis after losing it.
    public static let collapsedAngles = RigAngles(
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

    // MARK: - Solved poses

    public static let upright = uprightAngles.solved()
    public static let tuck = tuckAngles.solved()
    public static let carveLeft = carveLeftAngles.solved()
    public static let carveRight = carveRightAngles.solved()
    public static let airborne = airborneAngles.solved()
    public static let flipTuck = flipTuckAngles.solved()
    public static let landing = landingAngles.solved()
    public static let collapsed = collapsedAngles.solved()

    /// Every authored pose, for the invariants that must hold across all of them.
    public static let allAngles: [(name: String, angles: RigAngles)] = [
        ("upright", uprightAngles),
        ("tuck", tuckAngles),
        ("carveLeft", carveLeftAngles),
        ("carveRight", carveRightAngles),
        ("airborne", airborneAngles),
        ("flipTuck", flipTuckAngles),
        ("landing", landingAngles),
        ("collapsed", collapsedAngles)
    ]

    /// The pose for one frame, with no transition state.
    ///
    /// Retained for callers that hold no animator — the spray emitter asks for a pose from
    /// inside a layout pass, and a run's very first frame has nothing to ease from. Anything
    /// the player watches should go through `SkierAnimator` instead, which is what turns
    /// these authored poses into movement.
    public static func pose(for state: SkierState, cues: FeelCues) -> SkierPose {
        angles(for: state, cues: cues).solved()
    }

    static func angles(for state: SkierState, cues: FeelCues) -> RigAngles {
        if state.hasCrashed { return collapsedAngles }
        if !state.isGrounded { return airborneAngles }
        return uprightAngles.blended(toward: tuckAngles, amount: cues.tuckCompression)
    }
}
