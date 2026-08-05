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

    /// The run has ended *and* settled — see `RunOutcome.hasSettled`. Distinct from
    /// `hasCrashed`, which is true from the instant of the crash, through the slide.
    private(set) var isRunOver = false
    /// What ended the run, held from the crash frame until the next run starts.
    private(set) var endReason: RunOutcome.Reason?

    /// `@Observable` fires on assignment, not on change, so every field is written through this
    /// rather than assigned directly.
    ///
    /// It matters most exactly where the summary lives: once a run has settled, *nothing* moves
    /// again (ADR-026), yet the frame loop keeps calling this sixty times a second. Assigning
    /// unconditionally would invalidate the summary card on every one of those frames. Several
    /// fields — `flips`, `isAirborne`, `hasCrashed` — also change only a handful of times in a
    /// live run, so the HUD stops re-evaluating on them too.
    private func write<Value: Equatable>(_ value: Value, to field: ReferenceWritableKeyPath<RunTelemetry, Value>) {
        if self[keyPath: field] != value { self[keyPath: field] = value }
    }

    func update(from state: SkierState, isRunOver: Bool, endReason: RunOutcome.Reason?) {
        write(state.distanceM, to: \.distanceM)
        write(state.velocityX * 3.6, to: \.speedKmh)
        write(state.instability, to: \.instability)
        write(state.flips, to: \.flips)
        write(state.totalAirTimeS, to: \.airTimeS)
        write(!state.isGrounded, to: \.isAirborne)
        write(state.hasCrashed, to: \.hasCrashed)
        write(isRunOver, to: \.isRunOver)
        write(endReason, to: \.endReason)
    }

    /// The finished run's score, or `nil` while a run is still live.
    ///
    /// Optional and gated rather than always-available, because a score is only meaningful
    /// once there is nothing left to add to it. Nothing is snapshotted to build it: `isRunOver`
    /// is only true at the simulation's fixed point, where the fields it reads provably cannot
    /// move again (ADR-026).
    func finishedScore(conditions: RunConditions, peak: Peak) -> RunScore? {
        guard isRunOver else { return nil }
        return RunScore(
            distanceM: distanceM,
            airTimeS: airTimeS,
            flips: flips,
            snowState: conditions.snowState,
            peak: peak,
            endedInCrash: hasCrashed
        )
    }
}
