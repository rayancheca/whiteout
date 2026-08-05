import Foundation

/// Presentation cues for one frame, derived from the simulation.
///
/// Every value is normalised `0...1` so the renderer, the haptic engine and the audio
/// mixer can each scale it into their own units without re-deriving anything.
public struct FeelCues: Sendable, Equatable {

    /// How far ahead the camera should look. Rises with speed.
    public let cameraLead: Double
    /// Screen-shake magnitude. The primary channel for communicating surface roughness.
    public let shake: Double
    /// Motion-streak density.
    public let speedLines: Double
    /// Edge-noise level for audio: the hiss of skis on snow.
    public let carveLevel: Double
    /// Wind-noise level for audio, from apparent wind rather than reported wind.
    public let windLevel: Double
    /// How far the skier's silhouette should compress.
    public let tuckCompression: Double

    /// Everything at rest. Used for the frame before the first simulation step.
    public static let idle = FeelCues(
        cameraLead: 0, shake: 0, speedLines: 0,
        carveLevel: 0, windLevel: 0, tuckCompression: 0
    )
}

/// Turns simulation state into how the run should *feel*.
///
/// This exists as a separate, pure layer because feel is not physics. The simulation must
/// stay canonical — a server re-simulates it to verify scores — so nothing here may ever
/// influence it. Cues read the state and never write to it.
public enum FeelModel {

    /// Speed treated as "flat out" when normalising cues.
    public static let referenceSpeed = 26.0

    public static func cues(
        for state: SkierState,
        physics: SnowPhysics,
        weather: MountainWeather,
        isTucking: Bool
    ) -> FeelCues {
        let topSpeed = referenceSpeed * physics.topSpeedMultiplier
        let speedFraction = min(1, state.velocityX / max(topSpeed, 1))

        return FeelCues(
            cameraLead: easeIn(speedFraction),
            shake: shake(state, physics: physics, speedFraction: speedFraction),
            speedLines: rampUp(speedFraction, from: 0.58),
            carveLevel: state.isGrounded && !isTucking && !state.hasCrashed
                ? speedFraction * (0.35 + physics.grip * 0.65)
                : 0,
            windLevel: windLevel(state, weather: weather),
            tuckCompression: isTucking && state.isGrounded && !state.hasCrashed ? 1 : 0
        )
    }

    /// Screen shake.
    ///
    /// Two sources, deliberately. Surface roughness scales with the square of speed, which
    /// is how vibration actually grows and keeps slow sections calm. Instability adds a
    /// separate rising buzz as the edge starts to go — the EDGE meter says the same thing
    /// in numbers, but a player feels this one before they read that one, which is the
    /// difference between a fair crash and a surprising one.
    private static func shake(
        _ state: SkierState,
        physics: SnowPhysics,
        speedFraction: Double
    ) -> Double {
        guard !state.hasCrashed else { return 0 }
        guard state.isGrounded else {
            // Air is quiet. The contrast is what makes a jump feel like relief.
            return 0
        }

        let surface = physics.chatter * speedFraction * speedFraction
        // Only the last third of the edge meter starts to buzz, so the warning stays
        // meaningful rather than becoming constant background noise.
        let warning = pow(max(0, state.instability - 0.6) / 0.4, 1.6) * 0.75
        return min(1, surface + warning)
    }

    /// Apparent wind: the air the skier is actually moving through, not the forecast value.
    ///
    /// Standing still in a gale is loud; so is bombing a calm slope. Using the reported
    /// wind alone would leave a fast run through still air silent, which is wrong.
    private static func windLevel(_ state: SkierState, weather: MountainWeather) -> Double {
        let ownSpeedKmh = state.velocityX * 3.6
        let apparent = ownSpeedKmh + weather.windSpeedKmh * 0.55
        return min(1, apparent / 120)
    }

    /// Impact strength of a landing, `0...1`, or zero if this frame was not a landing.
    ///
    /// Reported as an event rather than a continuous cue because the camera punch, the
    /// haptic thump and the audio hit all need to fire exactly once.
    public static func landingImpact(previous: SkierState, current: SkierState) -> Double {
        guard !previous.isGrounded, current.isGrounded else { return 0 }
        let severity = abs(previous.velocityY) / 18
        return min(1, max(0, severity))
    }

    // MARK: - Curves

    /// Quadratic ease-in. Keeps low-speed cruising visually calm.
    private static func easeIn(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped
    }

    /// Zero below `threshold`, then a smooth ramp to 1.
    private static func rampUp(_ value: Double, from threshold: Double) -> Double {
        guard value > threshold else { return 0 }
        let span = max(0.0001, 1 - threshold)
        let t = min(1, (value - threshold) / span)
        return t * t * (3 - 2 * t)
    }
}
