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
}

/// The skeleton at one instant, as solved joint positions.
///
/// Coordinates are normalised so that `1.0` is the skier's standing height, with the origin
/// at the point where the ski meets the snow under the boot. `+x` is downhill, `+y` is up.
/// Normalising here rather than in points means the renderer owns exactly one scale number,
/// and the pose can be reasoned about — and asserted on — without a simulator.
///
/// Stored as named joints rather than a dictionary because this is rebuilt every frame at up
/// to 120 Hz, and a per-frame dictionary allocation is a real cost for no benefit.
///
/// **This type is an output, never an input to a blend.** Poses are produced by solving a
/// `RigAngles`, and any interpolation happens on the angles instead — see ADR-024. A pose
/// carries no method for combining itself with another one, because the obvious
/// implementation of that method is the bug T-111 existed to remove.
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
}
