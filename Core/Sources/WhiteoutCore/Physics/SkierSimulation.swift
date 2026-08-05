import Foundation

/// The player's complete state at one instant.
///
/// Every field is `let`. A frame does not mutate the skier; it derives the next skier from
/// the previous one. That is what makes a run reproducible from `(seed, input tape)` alone,
/// which in turn is what lets ghosts be 2 KB and lets a server verify a leaderboard score
/// by re-simulating it rather than trusting the client.
public struct SkierState: Sendable, Equatable {

    /// Distance travelled along the mountain, in metres. Doubles as the terrain coordinate.
    public let distanceM: Double
    /// World height, in metres. Compared against terrain height to resolve contact.
    public let altitudeM: Double

    public let velocityX: Double
    public let velocityY: Double

    /// Body angle in radians. On the ground this tracks the slope; in the air it spins.
    public let rotation: Double
    public let angularVelocity: Double

    public let isGrounded: Bool
    public let hasCrashed: Bool

    /// Seconds in the current jump. Zero while grounded.
    public let airTimeS: Double
    public let totalAirTimeS: Double
    /// Completed rotations across the run.
    public let flips: Int
    /// Rotation accumulated in the current jump, for flip counting.
    public let jumpRotation: Double

    /// Accumulated loss of edge, `0...1`. Reaching 1 is a crash.
    ///
    /// This is where the snowpack becomes a control decision rather than a stat: it fills
    /// at a rate set by `SnowPhysics.chatter`, so how long the player may stay tucked is
    /// dictated by the real weather.
    public let instability: Double

    public static func start(on terrain: TerrainGenerator) -> SkierState {
        let launchSpeed = 8.0
        return SkierState(
            distanceM: 0,
            altitudeM: terrain.height(at: 0),
            velocityX: launchSpeed,
            // Already descending. Starting at zero implies the skier is momentarily
            // flying level over a falling slope, which reads to the contact test as a
            // jump and launches them on frame one.
            velocityY: launchSpeed * tan(terrain.contactAngle(at: 0)),
            rotation: terrain.slopeAngle(at: 0),
            angularVelocity: 0,
            isGrounded: true,
            hasCrashed: false,
            airTimeS: 0,
            totalAirTimeS: 0,
            flips: 0,
            jumpRotation: 0,
            instability: 0
        )
    }

    public var speed: Double { sqrt(velocityX * velocityX + velocityY * velocityY) }
}

/// One frame of player input. A run is fully described by the seed plus a tape of these.
public struct SkierInput: Sendable, Equatable {
    /// Finger down. Tuck on the ground, rotate in the air.
    public let isHolding: Bool

    public init(isHolding: Bool) {
        self.isHolding = isHolding
    }
}

/// Advances the skier. Pure: no stored state, no clock, no randomness.
public enum SkierSimulation {

    // MARK: Tuning

    private enum Constant {
        static let gravity = 9.81
        /// Scales the v² drag term so packed snow reaches a sane terminal velocity.
        static let dragScale = 0.0062
        /// Frontal-area reduction from tucking. The entire reward for taking the risk.
        static let tuckDragFactor = 0.52
        /// Carve intensity applied automatically while upright. Held below most surfaces'
        /// grip so standing up is a controlled scrub rather than a permanent skid.
        static let carveIntensity = 0.5
        /// Backflip rate while holding in the air, radians per second.
        static let flipRate = -4.4
        /// How fast instability accumulates while tucked at full speed.
        static let instabilityRate = 0.55
        /// How fast standing upright recovers edge control.
        static let instabilityRecovery = 0.85
        /// Reference speed for normalising the instability build-up.
        static let referenceSpeed = 26.0
        /// Vertical impact speed above which even good form is punished.
        static let hardLandingSpeed = 22.0
        /// Ground clearance required before the skier is considered airborne.
        static let launchClearanceM = 0.12
    }

    /// Derives the next state. `delta` should already be clamped by the caller.
    public static func step(
        _ state: SkierState,
        input: SkierInput,
        terrain: TerrainGenerator,
        physics: SnowPhysics,
        delta: Double
    ) -> SkierState {
        guard !state.hasCrashed else { return coast(state, delta: delta) }

        return state.isGrounded
            ? stepGrounded(state, input: input, terrain: terrain, physics: physics, delta: delta)
            : stepAirborne(state, input: input, terrain: terrain, physics: physics, delta: delta)
    }

    // MARK: - Grounded

    private static func stepGrounded(
        _ state: SkierState,
        input: SkierInput,
        terrain: TerrainGenerator,
        physics: SnowPhysics,
        delta: Double
    ) -> SkierState {
        let slope = terrain.contactAngle(at: state.distanceM)

        // Gravity along the slope. `slope` is negative downhill, so negating it gives
        // a positive acceleration in the direction of travel.
        let gravityAccel = -Constant.gravity * sin(slope)

        let dragFactor = input.isHolding ? Constant.tuckDragFactor : 1.0
        let dragAccel = -Constant.dragScale * physics.drag * dragFactor
            * state.velocityX * state.velocityX

        var velocityX = max(0, state.velocityX + (gravityAccel + dragAccel) * delta)

        // Carving only happens standing up. It costs speed, and how much depends on the
        // surface: `carveePenaltyExponent` makes slush grab where packed snow would let go.
        if !input.isHolding {
            let retention = physics.speedRetention(carveIntensity: Constant.carveIntensity)
            velocityX *= pow(retention, delta)
        }

        let topSpeed = Constant.referenceSpeed * physics.topSpeedMultiplier
        velocityX = min(velocityX, topSpeed)

        let instability = nextInstability(state, input: input, physics: physics, speed: velocityX, delta: delta)
        if instability >= 1 {
            return crashed(state, velocityX: velocityX, instability: 1)
        }

        // Integrate ballistically first, then resolve against the ground. Over a convex
        // lip the terrain falls away faster than gravity and the skier is simply left
        // airborne — jumps emerge from the terrain rather than from scripted triggers.
        let nextDistance = state.distanceM + velocityX * delta
        let groundHeight = terrain.height(at: nextDistance)

        // Launch velocity comes from the slope the skier is *currently riding*, not from
        // the stored vertical velocity, which is zero on the first frame and immediately
        // after every landing. Using the stale value made the skier bounce down the hill.
        let slopeVelocityY = velocityX * tan(slope)
        let ballisticVelocityY = slopeVelocityY - Constant.gravity * delta
        let ballisticAltitude = state.altitudeM + ballisticVelocityY * delta

        // The clearance threshold is a ski length's worth of bump, not a hair's breadth.
        // A tighter value re-admits the texture octave through the back door.
        if ballisticAltitude > groundHeight + Constant.launchClearanceM {
            return SkierState(
                distanceM: nextDistance,
                altitudeM: ballisticAltitude,
                velocityX: velocityX,
                velocityY: ballisticVelocityY,
                rotation: state.rotation,
                angularVelocity: 0,
                isGrounded: false,
                hasCrashed: false,
                airTimeS: 0,
                totalAirTimeS: state.totalAirTimeS,
                flips: state.flips,
                jumpRotation: 0,
                instability: instability
            )
        }

        // Still in contact: follow the surface and align the body to it.
        let followVelocityY = (groundHeight - state.altitudeM) / delta
        let nextSlope = terrain.contactAngle(at: nextDistance)

        return SkierState(
            distanceM: nextDistance,
            altitudeM: groundHeight,
            velocityX: velocityX,
            velocityY: followVelocityY,
            rotation: approach(state.rotation, target: nextSlope, rate: 9, delta: delta),
            angularVelocity: 0,
            isGrounded: true,
            hasCrashed: false,
            airTimeS: 0,
            totalAirTimeS: state.totalAirTimeS,
            flips: state.flips,
            jumpRotation: 0,
            instability: instability
        )
    }

    private static func nextInstability(
        _ state: SkierState,
        input: SkierInput,
        physics: SnowPhysics,
        speed: Double,
        delta: Double
    ) -> Double {
        guard input.isHolding else {
            return max(0, state.instability - Constant.instabilityRecovery * delta)
        }
        // Scaled by speed as well as by surface: a slow tuck on ice is survivable, a fast
        // one is not, which keeps the decision live throughout a run instead of being
        // settled once by the weather.
        let speedFactor = min(1.5, speed / Constant.referenceSpeed)
        let build = physics.chatter * speedFactor * Constant.instabilityRate * delta
        return min(1, state.instability + build)
    }

    // MARK: - Airborne

    private static func stepAirborne(
        _ state: SkierState,
        input: SkierInput,
        terrain: TerrainGenerator,
        physics: SnowPhysics,
        delta: Double
    ) -> SkierState {
        let angularVelocity = input.isHolding ? Constant.flipRate : state.angularVelocity * 0.86
        let rotation = state.rotation + angularVelocity * delta
        let jumpRotation = state.jumpRotation + angularVelocity * delta

        let velocityY = state.velocityY - Constant.gravity * delta
        let distanceM = state.distanceM + state.velocityX * delta
        let altitudeM = state.altitudeM + velocityY * delta
        let groundHeight = terrain.height(at: distanceM)

        guard altitudeM <= groundHeight else {
            return SkierState(
                distanceM: distanceM,
                altitudeM: altitudeM,
                velocityX: state.velocityX,
                velocityY: velocityY,
                rotation: rotation,
                angularVelocity: angularVelocity,
                isGrounded: false,
                hasCrashed: false,
                airTimeS: state.airTimeS + delta,
                totalAirTimeS: state.totalAirTimeS + delta,
                flips: state.flips,
                jumpRotation: jumpRotation,
                instability: max(0, state.instability - Constant.instabilityRecovery * delta * 0.5)
            )
        }

        return resolveLanding(
            state,
            terrain: terrain,
            physics: physics,
            distanceM: distanceM,
            groundHeight: groundHeight,
            velocityY: velocityY,
            rotation: rotation,
            jumpRotation: jumpRotation
        )
    }

    private static func resolveLanding(
        _ state: SkierState,
        terrain: TerrainGenerator,
        physics: SnowPhysics,
        distanceM: Double,
        groundHeight: Double,
        velocityY: Double,
        rotation: Double,
        jumpRotation: Double
    ) -> SkierState {
        let slope = terrain.contactAngle(at: distanceM)
        // How far the body is from matching the surface it is arriving on. Landing a
        // backflip means bringing the rotation back around to the slope, not stopping it.
        let impactAngle = normaliseAngle(rotation - slope)
        let landedFlips = state.flips + Int(abs(jumpRotation) / (2 * .pi))

        let formIsGood = physics.absorbsLanding(impactAngle: impactAngle)
        // Float also decides how much vertical speed the snow can swallow. Deep powder
        // eats a hard landing that crust would reject outright.
        let survivableImpact = Constant.hardLandingSpeed * (0.45 + physics.float * 0.75)
        let impactIsSurvivable = abs(velocityY) <= survivableImpact

        guard formIsGood && impactIsSurvivable else {
            return SkierState(
                distanceM: distanceM,
                altitudeM: groundHeight,
                velocityX: state.velocityX * 0.35,
                velocityY: 0,
                rotation: rotation,
                angularVelocity: 0,
                isGrounded: true,
                hasCrashed: true,
                airTimeS: 0,
                totalAirTimeS: state.totalAirTimeS,
                flips: landedFlips,
                jumpRotation: 0,
                instability: 1
            )
        }

        // A clean landing still scrubs a little speed, scaled by how square it was.
        let cleanliness = 1 - min(1, abs(impactAngle) / 0.9)
        let retained = 0.82 + cleanliness * 0.18

        return SkierState(
            distanceM: distanceM,
            altitudeM: groundHeight,
            velocityX: state.velocityX * retained,
            velocityY: 0,
            rotation: slope,
            angularVelocity: 0,
            isGrounded: true,
            hasCrashed: false,
            airTimeS: 0,
            totalAirTimeS: state.totalAirTimeS,
            flips: landedFlips,
            jumpRotation: 0,
            instability: state.instability
        )
    }

    // MARK: - Helpers

    /// Slides to a stop after a crash so the camera settles instead of cutting.
    private static func coast(_ state: SkierState, delta: Double) -> SkierState {
        let velocityX = max(0, state.velocityX - 9 * delta)
        return SkierState(
            distanceM: state.distanceM + velocityX * delta,
            altitudeM: state.altitudeM,
            velocityX: velocityX,
            velocityY: 0,
            rotation: state.rotation,
            angularVelocity: 0,
            isGrounded: true,
            hasCrashed: true,
            airTimeS: 0,
            totalAirTimeS: state.totalAirTimeS,
            flips: state.flips,
            jumpRotation: 0,
            instability: 1
        )
    }

    private static func crashed(_ state: SkierState, velocityX: Double, instability: Double) -> SkierState {
        SkierState(
            distanceM: state.distanceM,
            altitudeM: state.altitudeM,
            velocityX: velocityX * 0.4,
            velocityY: 0,
            rotation: state.rotation,
            angularVelocity: 0,
            isGrounded: true,
            hasCrashed: true,
            airTimeS: 0,
            totalAirTimeS: state.totalAirTimeS,
            flips: state.flips,
            jumpRotation: 0,
            instability: instability
        )
    }

    /// Frame-rate independent easing toward a target.
    private static func approach(_ value: Double, target: Double, rate: Double, delta: Double) -> Double {
        value + (target - value) * (1 - exp(-rate * delta))
    }

    /// Wraps to `-π...π` so a rotation of 2π reads as square, not as maximally wrong.
    private static func normaliseAngle(_ angle: Double) -> Double {
        var wrapped = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if wrapped > .pi { wrapped -= 2 * .pi }
        if wrapped < -.pi { wrapped += 2 * .pi }
        return wrapped
    }
}
