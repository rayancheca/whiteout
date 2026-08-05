import Foundation

/// Carries the skier's pose *between* frames, so states transition instead of snapping.
///
/// The authored poses in `SkierRig` are instants; movement is the travel between them, and
/// travel needs somewhere to remember how far along it is. `SkierSimulation` cannot hold
/// that memory — a landing leaves no trace in `SkierState` once `isGrounded` flips back, and
/// putting a decay timer in the simulation would put presentation inside the thing a server
/// re-simulates. So the memory lives here, in the feel layer, under the same rule as
/// `FeelModel`: it reads state and cues, and writes to neither (ADR-025).
///
/// Every field is a normalised `0...1` weight easing toward a target. Composing weights
/// rather than running a state machine means two transitions can overlap — landing while
/// still holding a tuck, crashing mid-flip — without enumerating the pairs.
public struct SkierAnimator: Sendable, Equatable {

    /// How much of the racing tuck is applied.
    public let tuck: Double
    /// How much of the air pose has taken over from the ground pose.
    public let air: Double
    /// How balled-up the airborne skier is, from how hard they are rotating.
    public let flip: Double
    /// Landing absorption. Spikes on touchdown, then decays.
    public let landing: Double
    /// Collapse into the crash pose.
    public let crash: Double

    /// Everything at rest: a standing skier, mid-transition to nothing.
    public static let idle = SkierAnimator(tuck: 0, air: 0, flip: 0, landing: 0, crash: 0)

    // MARK: Tuning

    /// Exponential approach rates, per second. `ln(10)/rate` is the time to 90%.
    ///
    /// Chosen against measured per-frame joint travel, not by feel alone. The head and the
    /// pole tip sit at the ends of the bone chain and so accumulate every rotation upstream
    /// of them: a first pass at `tuckIn = 17` moved the weight 25% in a single frame, which
    /// swept the head 5.2 points and the pole tip 6.6 at a 30-point body. Fast enough to read
    /// as a cut rather than a fold. These land the head near 3.8 points a frame instead.
    private enum Rate {
        /// Dropping into a tuck is a commitment and reads best as decisive — 90% in 0.19 s.
        static let tuckIn = 12.0
        /// Standing back up is slower; the body unfolds against the wind. 90% in 0.29 s.
        static let tuckOut = 8.0
        /// Takeoff cannot look soft, so this stays as quick as the tuck.
        static let air = 12.0
        static let flip = 9.0
        /// Absorption springs back over roughly a third of a second.
        static let landing = 7.5
        static let crash = 10.0
    }

    private enum Constant {
        /// Metres of travel per full flex-and-extend cycle.
        ///
        /// Driven by distance rather than by a clock, which gets two things for free: the
        /// rhythm speeds up with the skier instead of running at a fixed cadence regardless
        /// of speed, and the phase is a pure function of `distanceM` — so it needs no memory
        /// and stays identical on a replay at any frame rate.
        static let carveWavelengthM = 17.0
        /// Angular speed treated as a full commitment to the rotation.
        ///
        /// Matches `SkierSimulation`'s flip rate, so holding through a jump reaches a fully
        /// balled-up pose and a loose tumble off a lip does not.
        static let fullFlipRate = 4.4
    }

    /// Advances one frame.
    ///
    /// `landingImpact` is the value `FeelModel.landingImpact` reported for this frame, and is
    /// zero on every frame that is not a touchdown. It is taken as an impulse rather than
    /// re-derived here because the camera punch and the haptic thump already key off exactly
    /// that number, and three consumers disagreeing about when a landing happened is how a
    /// landing ends up feeling smeared.
    public func advanced(
        for state: SkierState,
        cues: FeelCues,
        landingImpact: Double,
        delta: Double
    ) -> SkierAnimator {
        let flipTarget = state.isGrounded
            ? 0
            : min(1, abs(state.angularVelocity) / Constant.fullFlipRate)

        return SkierAnimator(
            tuck: approach(
                tuck,
                target: cues.tuckCompression,
                rate: cues.tuckCompression > tuck ? Rate.tuckIn : Rate.tuckOut,
                delta: delta
            ),
            air: approach(air, target: state.isGrounded ? 0 : 1, rate: Rate.air, delta: delta),
            flip: approach(flip, target: flipTarget, rate: Rate.flip, delta: delta),
            // Impulse first, then decay, so a landing that arrives mid-decay from a previous
            // one reads as the harder of the two rather than as their sum.
            landing: max(
                landingImpact,
                approach(landing, target: 0, rate: Rate.landing, delta: delta)
            ),
            crash: approach(crash, target: state.hasCrashed ? 1 : 0, rate: Rate.crash, delta: delta)
        )
    }

    /// Composes the frame's pose from the authored ones.
    ///
    /// Layered outermost-last, so the strongest override wins: whatever the legs were doing,
    /// a crash folds it up. Every step is a `RigAngles` blend, and the chain is solved exactly
    /// once at the end — bones cannot contract at any depth of the stack (ADR-024).
    public func angles(for state: SkierState, cues: FeelCues) -> RigAngles {
        // Ground: a carve rhythm under the tuck, then absorption over the top of both.
        let carveBlend = (sin(state.distanceM * 2 * .pi / Constant.carveWavelengthM) + 1) / 2
        let carving = SkierRig.carveLeftAngles
            .blended(toward: SkierRig.carveRightAngles, amount: carveBlend)

        // `carveLevel` is already "grounded, not tucking, not crashed", scaled by speed and
        // by grip — so the rhythm fades out on ice and at a crawl without a second rule here.
        let ground = SkierRig.uprightAngles
            .blended(toward: carving, amount: cues.carveLevel)
            .blended(toward: SkierRig.tuckAngles, amount: tuck)
            .blended(toward: SkierRig.landingAngles, amount: landing)

        let airborne = SkierRig.airborneAngles
            .blended(toward: SkierRig.flipTuckAngles, amount: flip)

        return ground
            .blended(toward: airborne, amount: air)
            .blended(toward: SkierRig.collapsedAngles, amount: crash)
    }

    public func pose(for state: SkierState, cues: FeelCues) -> SkierPose {
        angles(for: state, cues: cues).solved()
    }

    // MARK: - Helpers

    /// Frame-rate independent easing toward a target.
    ///
    /// The same exponential form `SkierSimulation` uses to align the body to the slope, for
    /// the same reason: a plain `value += (target - value) * rate * delta` converges at a
    /// speed that depends on the frame rate, so a 120 Hz phone and a 60 Hz one would animate
    /// the same tuck differently.
    private func approach(_ value: Double, target: Double, rate: Double, delta: Double) -> Double {
        value + (target - value) * (1 - exp(-rate * delta))
    }

    private init(tuck: Double, air: Double, flip: Double, landing: Double, crash: Double) {
        self.tuck = tuck
        self.air = air
        self.flip = flip
        self.landing = landing
        self.crash = crash
    }
}
