import Foundation

/// When a run is over, and what ended it.
///
/// Both answers are *derived* rather than stored. A run end is not a new piece of state the
/// simulation has to carry — it is a question you can ask of two values the caller already
/// holds, which is why `restart()` gains nothing to reset and a replay needs no extra tape.
public enum RunOutcome {

    /// Why a run ended.
    ///
    /// An enum rather than a `Bool` because the honest answer already has two values, and the
    /// HUD has been printing "caught an edge" over blown landings. `RunScore.endedInCrash`
    /// carries the coarser distinction downstream, so a future non-crash ending (T-116) adds a
    /// case here rather than a parallel channel.
    public enum Reason: Sendable, Equatable {
        case caughtAnEdge
        case blewTheLanding

        public var headline: String {
            switch self {
            case .caughtAnEdge: "CAUGHT AN EDGE"
            case .blewTheLanding: "BLEW THE LANDING"
            }
        }
    }

    /// The `SkierAnimator.crash` weight at which the collapse counts as read.
    ///
    /// Reached in `ln(10) / Rate.crash` = 0.233 s. Coupled to the fold on purpose: the beat
    /// exists so the collapse can be *seen* before anything covers it, so retuning the fold has
    /// to move the beat with it. `Rate` is private to the animator, so a test pins the
    /// relationship rather than a comment asserting it.
    public static let collapseFloor = 0.9

    /// The run-ending edge. `nil` on every frame that is not the frame the run ended.
    ///
    /// Shaped like `FeelModel.landingImpact(previous:current:)` — an event derived by comparing
    /// two states, so no field is added to `SkierState` and the value a server re-simulates to
    /// verify a score is untouched.
    public static func reason(previous: SkierState, current: SkierState) -> Reason? {
        guard !previous.hasCrashed, current.hasCrashed else { return nil }
        // A crash entered from the air is a landing the skier failed to ride out; one entered
        // from the ground is the edge finally letting go.
        return previous.isGrounded ? .caughtAnEdge : .blewTheLanding
    }

    /// Whether the run has finished and its summary may be shown.
    ///
    /// Two conditions that already exist in the frame, each covering the other's blind spot.
    ///
    /// `velocityX == 0` is an exact fixed point, not an approximation: `coast` clamps with
    /// `max(0, …)`, and every other field of a stopped crash is a constant expression of
    /// itself. So the state cannot move again, and a score read on any later frame equals the
    /// one read on the first — which is why nothing here is snapshotted and no latch can go
    /// stale. `aSettledRunCannotDrift` is what holds that property.
    ///
    /// `collapse` guarantees the fold is legible first, and is what covers a crash that stops
    /// almost immediately — the slide alone is as short as 0.22 s.
    ///
    /// Takes a bare weight rather than a `SkierAnimator` so physics never depends on the render
    /// layer: a server re-simulating a run to verify it has no animator.
    public static func hasSettled(_ state: SkierState, collapse: Double) -> Bool {
        state.hasCrashed && state.velocityX == 0 && collapse >= collapseFloor
    }
}
