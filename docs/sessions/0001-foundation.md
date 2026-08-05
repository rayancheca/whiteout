# Session 0001 — Foundation

**Date:** 2026-08-05 · **Milestone:** M0 · **Outcome:** M0 complete, infrastructure in place

## Built

- `WhiteoutCore`: indexed seeded randomness, terrain generation, Altitude Translation,
  Snow State Model, `SnowPhysics`, OKLCH palette generator, solar position, Open-Meteo
  client, geohash bucketing, Peaks, `SkierSimulation`, `FeelModel`, `RunScore`.
- iOS app: SpriteKit renderer with parallax and aerial perspective, SwiftUI shell,
  conditions card, EDGE meter, `RunFeedback` (CoreHaptics + procedural AVAudioEngine).
- Project infrastructure: git, public remote, `CLAUDE.md`, docs suite, `/session-start`,
  `/session-end`, `scripts/verify.sh`, settings hooks.
- 85 tests, 13 suites, ~30 ms.

## Bugs found by running, not reasoning

Worth recording as a pattern — the suite alone would not have caught any of these.

1. **Bouncing skier.** Launch detection compared a ballistic path against stored
   `velocityY`, which is 0 on frame one and after every landing. A skier at 8 m/s down a
   −0.29 rad slope already carries −2.4 m/s vertically, so it "launched", landed, reset,
   relaunched. Fixed by deriving launch velocity from the slope being ridden.

2. **Texture read as terrain.** The fine octave has a sub-metre wavelength; `slopeAngle`'s
   ±0.5 m window saw sastrugi as ~0.5 rad cliffs. Added `contactAngle` sampling over a
   1.7 m ski length. See ADR-012.

3. **Free carving.** `speedRetention` penalised only demand above `grip`, and auto-carve
   (0.62) sat below packed's grip (0.85) — so carving cost nothing and tuck/carve were
   identical. Surfaced as "hits top speed while upright". The scrub formula was also
   inverted, scrubbing hardest on ice where a ski cannot scrub. See ADR-013.

4. **Audio SIGTRAP.** `makeNoiseNode` was a static member of a `@MainActor` type and
   silently inherited isolation; the render block called `swift_task_checkIsolatedSwift` on
   the audio thread and trapped. A comment stating the constraint did not prevent it. See
   ADR-011.

## Measured, and it changed the design

At a fixed 2,800 m, three real cities returned only two distinct snow states, and through
the northern summer four of six states are unreachable. That measurement produced the Peaks
system — altitude restores the model's full range from the same real weather, and adds a
progression axis that cannot be sold because it changes speed. ADR-009.

## Test failures that were the test's fault, not the code's

Three, all worth noting because they cost real time:

- Impact angle is measured *relative to the slope*; pinning an absolute rotation left the
  actual angle at the mercy of the terrain.
- Wind exposure more than doubles with altitude, so a "calm" 27 km/h fixture became a
  58 km/h scoured ridge and classified as ice.
- 14 °C at sea level is already below freezing at 2,800 m, so a "rain" fixture never rained.

Lesson: fixtures for this model must be expressed in terms of what they intend to measure,
because the translation layer changes them substantially.

## Decisions

ADR-001 through ADR-016. See `docs/DECISIONS.md`.

## Left for next session

T-101 — skier art and rig. Everything else in M1 follows from having a real character.
