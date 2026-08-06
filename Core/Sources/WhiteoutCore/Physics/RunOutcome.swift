import Foundation

/// When a run is over, and what ended it.
///
/// Both answers are *derived* rather than stored. A run end is not a new piece of state the
/// simulation has to carry — it is a question you can ask of values the caller already
/// holds, which is why `restart()` gains nothing to reset and a replay needs no extra tape.
public enum RunOutcome {

    /// Why a run ended.
    ///
    /// An enum rather than a `Bool` because the honest answer has never had only two values,
    /// and the HUD has been printing "caught an edge" over blown landings. `RunScore.endedInCrash`
    /// carries the coarser distinction downstream, which is why `ranOutOfSpeed` needed no new
    /// channel to reach the score: a stall leaves `hasCrashed` false, and that was already the
    /// field the score reads.
    public enum Reason: Sendable, Equatable {
        case caughtAnEdge
        case blewTheLanding
        /// The mountain ran uphill faster than the run was carrying. Not a crash — nothing
        /// broke and nobody fell; the skier simply has no way to move again.
        case ranOutOfSpeed

        public var headline: String {
            switch self {
            case .caughtAnEdge: "CAUGHT AN EDGE"
            case .blewTheLanding: "BLEW THE LANDING"
            case .ranOutOfSpeed: "RAN OUT OF SPEED"
            }
        }

        /// Whether the body actually went down.
        ///
        /// The crash haptic and the collapse fold key off this rather than off "the run ended",
        /// because a stall ends a run with the skier still standing. Thumping the taptic engine
        /// there would be reporting an impact that never happened.
        public var isCrash: Bool { self != .ranOutOfSpeed }
    }

    /// The `SkierAnimator.crash` weight at which the collapse counts as read.
    ///
    /// Reached in `ln(10) / Rate.crash` = 0.233 s. Coupled to the fold on purpose: the beat
    /// exists so the collapse can be *seen* before anything covers it, so retuning the fold has
    /// to move the beat with it. `Rate` is private to the animator, so a test pins the
    /// relationship rather than a comment asserting it.
    ///
    /// It gates only the crash ending. A stall has no fold to wait for — see `hasStalled`.
    public static let collapseFloor = 0.9

    /// The run-ending edge. `nil` on every frame that is not the frame the run ended.
    ///
    /// Shaped like `FeelModel.landingImpact(previous:current:)` — an event derived by comparing
    /// two states, so no field is added to `SkierState` and the value a server re-simulates to
    /// verify a score is untouched. Both endings are the same shape: a predicate that was false
    /// and is now true.
    public static func reason(
        previous: SkierState,
        current: SkierState,
        terrain: TerrainGenerator
    ) -> Reason? {
        if !previous.hasCrashed, current.hasCrashed {
            // A crash entered from the air is a landing the skier failed to ride out; one
            // entered from the ground is the edge finally letting go.
            return previous.isGrounded ? .caughtAnEdge : .blewTheLanding
        }
        if !hasStalled(previous, terrain: terrain), hasStalled(current, terrain: terrain) {
            return .ranOutOfSpeed
        }
        return nil
    }

    /// Whether the skier has come to rest somewhere the mountain cannot start them again.
    ///
    /// The counter-slope is the entire condition, and it is exact rather than a heuristic.
    /// `stepGrounded` accelerates along the slope by `-gravity * sin(contactAngle)` and drag
    /// vanishes at zero speed, so a stopped skier is driven by that one term: a non-negative
    /// contact angle gives a non-positive acceleration, `max(0, …)` clamps it back to zero, and
    /// the distance therefore does not change — which leaves the angle identical on the next
    /// frame. The state is its own successor. Instability cannot rescue it either: the build
    /// term scales with speed, so a held tuck at a standstill never reaches a crash.
    ///
    /// That is what makes this answerable on a single frame, with no timer and no stored
    /// "stopped since" instant to go stale. Measured over 120 seeds × 6 surfaces × 2 input
    /// tapes: 206 stalls, 1.17 M frames after the first one, and the predicate never went false
    /// again once true; 183 of them driven a further 20 s of alternating input at the coarsest
    /// delta the loop can deliver moved the skier 0.0 m.
    ///
    /// The angle is read through `contactAngle` and not `slopeAngle` because that is the
    /// function the physics itself integrates. Asking a different question than the simulation
    /// answers is how a predicate and its subject drift apart.
    ///
    /// `isGrounded` is not redundant today — nothing in flight can reach zero horizontal speed —
    /// but a falling skier is not a stuck one, and pinning that here means a future change to
    /// the launch or landing path breaks a test instead of silently ending runs mid-jump.
    public static func hasStalled(_ state: SkierState, terrain: TerrainGenerator) -> Bool {
        !state.hasCrashed
            && state.isGrounded
            && state.velocityX == 0
            && terrain.contactAngle(at: state.distanceM) >= 0
    }

    /// Whether the run has finished and its summary may be shown.
    ///
    /// Two ways for a run to be over, and the same underlying reason in both: the simulation
    /// has reached a fixed point, so the score can no longer change.
    ///
    /// **A settled crash.** `velocityX == 0` is exact, not an approximation: `coast` clamps
    /// with `max(0, …)`, and every other field of a stopped crash is a constant expression of
    /// itself. `collapse` guarantees the fold is legible first, and covers a crash that stops
    /// almost immediately — the slide alone is as short as 0.22 s. `aSettledRunCannotDrift`
    /// holds that property.
    ///
    /// **A stall.** The skier stopped on a counter-slope and cannot be restarted. There is no
    /// fold to wait for and nothing to become legible, because the readable event *is* the
    /// world stopping — so this ending needs no equivalent of `collapseFloor`, and inventing a
    /// beat for it would mean storing an instant, which is the one thing ADR-026 buys us out of.
    ///
    /// Terrain enters here rather than a snapshot of the local gradient so nothing has to be
    /// carried across frames. It is only ever sampled on a frame where the skier is already
    /// stopped and uncrashed — both `||` and `hasStalled`'s own leading clauses short-circuit —
    /// so a live run pays nothing for it.
    ///
    /// Takes a bare collapse weight rather than a `SkierAnimator` so physics never depends on
    /// the render layer: a server re-simulating a run to verify it has no animator, but it does
    /// have the terrain, which it must generate from the seed anyway.
    public static func hasSettled(
        _ state: SkierState,
        collapse: Double,
        terrain: TerrainGenerator
    ) -> Bool {
        let crashHasSettled = state.hasCrashed && state.velocityX == 0 && collapse >= collapseFloor
        return crashHasSettled || hasStalled(state, terrain: terrain)
    }
}
