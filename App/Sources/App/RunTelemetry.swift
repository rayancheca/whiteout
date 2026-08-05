import Observation
import WhiteoutCore

/// Live run state, published from the SpriteKit frame loop to the SwiftUI HUD.
///
/// A narrow bridge on purpose. The simulation stays a pure function over `SkierState` in
/// `WhiteoutCore`; this exposes only what the HUD draws, so nothing in the UI layer can
/// reach in and perturb the physics that a server will later re-simulate to verify a score.
@Observable
@MainActor
final class RunTelemetry {

    private(set) var distanceM: Double = 0
    private(set) var speedKmh: Double = 0
    /// `0...1`. How close the skier is to losing an edge.
    private(set) var instability: Double = 0
    private(set) var flips: Int = 0
    private(set) var airTimeS: Double = 0
    private(set) var isAirborne = false
    private(set) var hasCrashed = false

    func update(from state: SkierState) {
        distanceM = state.distanceM
        speedKmh = state.velocityX * 3.6
        instability = state.instability
        flips = state.flips
        airTimeS = state.totalAirTimeS
        isAirborne = !state.isGrounded
        hasCrashed = state.hasCrashed
    }

    func score(conditions: RunConditions, peak: Peak) -> RunScore {
        RunScore(
            distanceM: distanceM,
            airTimeS: airTimeS,
            flips: flips,
            snowState: conditions.snowState,
            peak: peak,
            endedInCrash: hasCrashed
        )
    }
}
