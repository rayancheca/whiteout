import Foundation

/// The tuning constants a `SnowState` hands to the simulation.
///
/// Every field is a multiplier or a normalised 0–1 weight so states stay comparable and a
/// designer can reason about them side by side. Nothing here is authored per-level: the
/// weather picks the state, the state picks these numbers, the numbers change the feel.
public struct SnowPhysics: Sendable, Equatable {

    /// Edge hold. Scales how fast a carve can change heading before it washes out.
    public let grip: Double

    /// Landing forgiveness. High float absorbs a bad angle; low float rejects it.
    public let float: Double

    /// Velocity-squared drag coefficient. The dominant term at speed.
    public let drag: Double

    /// Ceiling on achievable speed, relative to packed snow.
    public let topSpeedMultiplier: Double

    /// Control noise and camera shake at speed. Communicates surface texture through feel
    /// rather than through a HUD readout.
    public let chatter: Double

    /// Spray/plume particle density thrown by the edges.
    public let sprayDensity: Double

    /// How much *harder* carving is punished as it approaches the grip limit.
    /// Above 1, pushing a turn past the surface's tolerance costs disproportionate speed —
    /// this is what makes slush feel grabby instead of merely slow.
    public let carveePenaltyExponent: Double

    /// The physical profile for a snowpack state.
    ///
    /// The numbers encode a real tradeoff rather than a difficulty dial: powder is the
    /// forgiving surface *and* the slow one, ice is lethal *and* the fastest. Neither is
    /// strictly better, so "good conditions" is a matter of what the player is chasing —
    /// distance, or a clean run.
    public static func profile(for state: SnowState) -> SnowPhysics {
        switch state {
        case .powder:
            SnowPhysics(
                grip: 0.72, float: 1.00, drag: 0.85,
                topSpeedMultiplier: 0.86, chatter: 0.05,
                sprayDensity: 1.00, carveePenaltyExponent: 0.9
            )
        case .packed:
            SnowPhysics(
                grip: 0.85, float: 0.62, drag: 0.55,
                topSpeedMultiplier: 1.00, chatter: 0.18,
                sprayDensity: 0.45, carveePenaltyExponent: 1.0
            )
        case .crust:
            SnowPhysics(
                grip: 0.48, float: 0.20, drag: 0.42,
                topSpeedMultiplier: 1.12, chatter: 0.78,
                sprayDensity: 0.30, carveePenaltyExponent: 1.6
            )
        case .slush:
            SnowPhysics(
                grip: 0.66, float: 0.74, drag: 1.25,
                topSpeedMultiplier: 0.78, chatter: 0.22,
                sprayDensity: 0.85, carveePenaltyExponent: 1.8
            )
        case .ice:
            SnowPhysics(
                grip: 0.30, float: 0.10, drag: 0.30,
                topSpeedMultiplier: 1.25, chatter: 0.92,
                sprayDensity: 0.12, carveePenaltyExponent: 1.4
            )
        case .windSlab:
            SnowPhysics(
                grip: 0.58, float: 0.55, drag: 0.62,
                topSpeedMultiplier: 0.95, chatter: 0.60,
                sprayDensity: 0.70, carveePenaltyExponent: 1.3
            )
        }
    }
}

extension SnowPhysics {

    /// Speed retained through a carve of `intensity` (0 = straight, 1 = maximum input).
    ///
    /// Returns a multiplier in `0...1`. The exponent is what separates the surfaces: on
    /// packed snow the cost of a hard turn is close to linear, while on slush it climbs
    /// steeply, so the correct slush technique is to under-steer early rather than
    /// muscle the turn late.
    public func speedRetention(carveIntensity intensity: Double) -> Double {
        let clamped = min(max(intensity, 0), 1)
        let demand = pow(clamped, carveePenaltyExponent)

        // Every carve sheds some speed — shedding speed is what a carve is *for*. Grip
        // scales it, because scrubbing requires an edge that actually bites: firm snow
        // lets a skier wash off real speed, while ice simply lets them slide, which is
        // the physical reason ice runs fast and frightening.
        //
        // Penalising only over-demand (the earlier form) meant any carve below the grip
        // limit was free, so on packed snow tucking and carving were indistinguishable
        // and the game's one decision collapsed.
        let scrub = demand * grip * 0.18

        // Past the grip limit the edge lets go and the turn becomes a skid.
        let overDemand = max(0, demand - grip)

        return max(0.15, 1 - scrub - overDemand * 1.4)
    }

    /// Whether a landing at `impactAngle` radians off the slope normal is absorbed.
    ///
    /// Float is the whole story: the same jump that powder swallows will wash out on
    /// crust, which is what makes a storm day feel generous and a refreeze day feel mean.
    public func absorbsLanding(impactAngle: Double) -> Bool {
        let tolerance = 0.18 + float * 0.55
        return abs(impactAngle) <= tolerance
    }
}
