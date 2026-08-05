import Foundation

/// The slope surface, as a pure function of horizontal distance.
///
/// Nothing is pre-generated and nothing is stored. `height(at:)` can be asked about metre
/// 50,000 without having evaluated metre 1, which is what allows a run to be replayed,
/// raced against a ghost, or verified on a server from nothing but a seed and an input
/// tape. It also means memory use is constant regardless of run length.
public struct TerrainGenerator: Sendable {

    /// Average downhill gradient. Negative because the mountain descends.
    private static let baseGradient: Double = -0.30

    private let macro: SeededRandom   // ridgelines and pitch changes
    private let micro: SeededRandom   // rollers and moguls
    private let features: SeededRandom // jumps, cliffs, prop placement

    /// Surface roughness, scaled by snowpack state.
    private let roughness: Double

    public init(seed: UInt64, snowState: SnowState) {
        let root = SeededRandom(seed: seed)
        self.macro = root.domain("terrain.macro")
        self.micro = root.domain("terrain.micro")
        self.features = root.domain("terrain.features")
        self.roughness = Self.roughness(for: snowState)
    }

    /// Surface height at horizontal distance `x`, in metres.
    public func height(at x: Double) -> Double {
        let descent = x * Self.baseGradient

        // Large-scale pitch: the difference between a flat traverse and a steep face.
        let ridge = macro.fbm(at: x, octaves: 3, frequency: 0.0016, persistence: 0.55) * 78

        // Mid-scale rolls that generate air and read as terrain the player can plan against.
        let rollers = macro.fbm(at: x, octaves: 2, frequency: 0.011, persistence: 0.5) * 9

        // Fine chatter. Scaled by snow state so the *same seed* is glassy on ice and
        // smoothed flat under fresh powder — this is the surface model reaching into
        // geometry, not just into physics.
        //
        // Frequency here is the whole point: at ~1.6 the base wavelength is well under a
        // metre, which is the scale of sastrugi and frozen chunder. An earlier value of
        // 0.14 gave a 7 m wavelength — that is a roller, not a surface, and it left the
        // roughness term with nothing to modulate.
        let texture = micro.fbm(at: x, octaves: 2, frequency: 1.6, persistence: 0.45) * roughness

        return descent + ridge + rollers + texture
    }

    /// Local slope angle in radians at `x`, from a central difference over 1 m.
    ///
    /// Fine enough to see real curvature. Not what the skier rides — use `contactAngle`
    /// for that.
    public func slopeAngle(at x: Double) -> Double {
        let delta = 0.5
        let rise = height(at: x + delta) - height(at: x - delta)
        return atan2(rise, delta * 2)
    }

    /// The angle the skier's edges actually sit at, sampled over a ski length.
    ///
    /// A ski is a rigid ~1.7 m plank: it spans surface texture rather than following it.
    /// Sampling contact at the finer `slopeAngle` window instead makes the fine octave —
    /// which has a sub-metre wavelength — register as slopes near 0.5 rad, so the skier
    /// reads every sastruga as a cliff and launches off flat ground. Bridging is not a
    /// smoothing hack; it is what the equipment physically does.
    public func contactAngle(at x: Double) -> Double {
        let skiHalfLengthM = 0.85
        let rise = height(at: x + skiHalfLengthM) - height(at: x - skiHalfLengthM)
        return atan2(rise, skiHalfLengthM * 2)
    }

    /// Whether a jump feature starts in the metre beginning at `x`.
    ///
    /// Placement is deterministic per 40 m cell, so the same seed always produces the same
    /// course, and a minimum gradient is required so kickers never appear on a flat runout
    /// where they would be unhittable.
    public func hasKicker(at x: Double) -> Bool {
        let cell = UInt64(bitPattern: Int64((x / 40).rounded(.down)))
        guard features.chance(0.34, at: cell) else { return false }
        return slopeAngle(at: x) < -0.12
    }

    /// Fine-texture amplitude for a snowpack state, in metres.
    ///
    /// Fresh snow physically fills and smooths the surface; wind and refreeze sculpt it
    /// into sastrugi and frozen chunder. The values are small on purpose — this is felt
    /// through the controller far more than it is seen, and they are held to the real
    /// scale of these features (roughly 5–35 cm) rather than the near-metre amplitudes
    /// an earlier pass used, which would have read as terrain instead of texture.
    private static func roughness(for state: SnowState) -> Double {
        switch state {
        case .powder: 0.05
        case .packed: 0.10
        case .crust: 0.28
        case .slush: 0.15
        case .ice: 0.20
        case .windSlab: 0.35
        }
    }
}
