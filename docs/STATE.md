# State

**Updated:** Session 0002 · 2026-08-05
**Milestone:** M1 (Vertical Slice) — T-101 and T-110 done

---

## Where the project is

The skier is a real, jointed silhouette instead of a black capsule, and the game now fills
the whole screen. The rig is a pure pose solver in `WhiteoutCore`, so proportion and
legibility are unit tests rather than screenshots.

**109 tests passing** across 16 suites in ~30 ms. iOS build green.

## Verified working

Confirmed by running it and measuring pixels, not by reasoning about it:

- **Fullscreen.** Content measured at 874 × 402 pt on iPhone 17 Pro, 100% of the display.
  Before the fix it was 564 × 376 — 36% of the width was black bars.
- **Safe area.** The conditions card clears the Dynamic Island in landscape; the canvas
  still runs edge to edge behind it.
- **The rig reads.** Head, torso, arms, ski and pole all legible at run scale.
- **The tuck is a real shape change.** Measured from screenshots: upright silhouette 32.0 pt,
  tucked 16.7 pt — a ratio of 0.52. The placeholder faked 0.68 with a vertical squash, which
  shortens the standing shape without changing it.
- **The ski lies on the snow** after the drawn-length angle fix (ADR-020).
- Everything from Session 0001 still holds: live Open-Meteo → physics, offline fallback,
  tuck/carve/crash/restart.

## Written but NOT verified

- **Haptics.** `RunFeedback` compiles and does not crash, but the simulator has no taptic
  engine. Entirely unverified. Do not claim otherwise.
- **Procedural audio.** The engine starts without crashing; nobody has heard it.
- **Landscape-right safe area.** Verified in landscape-left only. The insets come from
  `GeometryReader`, which is orientation-correct by construction, but it has not been seen.
- **The night palette on screen.** The legibility guarantee is asserted in tests across 8
  palettes; only daytime packed snow has actually been looked at.

Haptics and audio need T-109 (device TestFlight) to confirm.

## Known rough edges

- **Bones stay rigid in the authored poses but not mid-blend.** `blended(toward:amount:)`
  interpolates joint *positions*, which shortens every bone at intermediate `t` — measured
  at ~6.6% of torso length at `t = 0.5`, on every frame of every tuck entry and exit. Not
  visible at 30 pt, but it is the reason T-111 exists. The fix is to blend in angle space,
  which is the space T-102 needs anyway.
- The rig has four poses with no transitions — switching between them is instantaneous.
  That is exactly T-102.
- **`FeelCues.tuckCompression` is zeroed in the air** (`FeelModel.swift:56`). Harmless today
  because `pose(for:cues:)` returns the air pose before consulting it, but T-102 cannot
  drive an input-responsive air pose (a held flip) from that cue — the information is
  already destroyed. It needs the raw input, not the cue.
- **A flip has no up/down cue.** The head and the ski are both near-symmetric in profile,
  so an inverted skier looks much like an upright one. T-102 needs an asymmetric element.
- Visuals remain systemically correct but artistically thin: no volumetric light, no depth
  of field, no snow surface detail (T-103, T-104).
- Speed reads slightly high (~60–85 km/h). Worth a tuning pass on device.
- The location permission prompt still appears before any context is given.

## Surprises worth carrying forward

Both of this session's real findings came from *measuring*, not from reading code:

1. **The app had never been fullscreen.** No line of source was wrong — the bug lived in the
   *absence* of a plist key, so there was nothing to read. It survived all of M0 because
   letterboxing looks like a deliberate frame until you measure it. Lesson: measure the
   canvas, do not assume the screen you asked for is the screen you got.

2. **The legibility test passed while testing the wrong thing.** The first version asserted
   contrast against `skyHorizon` and `skyZenith` and went green. But the skier never reaches
   the sky — it needs ~111 m of relative altitude — and is in fact drawn against the nearest
   ridge band the entire run. A green test against the wrong backdrop is worse than no test,
   because it retires the question. Lesson: before asserting a visual property, verify what
   is *actually behind* the thing you are asserting about.

3. **A tolerance band is not a rigidity check.** The first `limbsStayAttached` test allowed
   each limb a range of 0.05–0.32 and passed — while the upper arm was 51% shorter in the
   tuck than standing and the forearm 67% longer. A test wide enough never to fail asserts
   nothing. The replacement compares every pose against the standing one, and the poses are
   now *built* from a single bone table so the property is structural rather than merely
   asserted.

The Session 0001 pattern held again: reasoning missed all three, measurement caught them.
Worth noting the review that surfaced #3 was only possible because the rig lives in Core as
plain geometry — the same defect inside a SpriteKit node would have needed an artist's eye.

## Next

**T-102 — Skier animation states.** The rig exposes `upright`, `tuck`, `airborne` and
`collapsed` plus a `blended(toward:amount:)`, so T-102 is transitions and timing, not new
geometry: easing between poses, a real crash tumble, carve lean, and flip tracking in the
air.

Then T-103 (art direction) and T-106 (audio) are both unblocked and independent.

## Environment notes

- Simulator: iPhone 17 Pro `10C15FE0-3D9A-40D5-9E45-C0702E906DF3`, landscape 874 × 402 pt
- Simulator builds need `CODE_SIGNING_ALLOWED=NO`; no signing team configured
- Screenshots must be rotated with `sips -r -90` (device portrait, app landscape)
- The skier's screen X moves from 0.34 to 0.20 of width as speed rises, so a fixed crop
  window will lose it — locate it by thresholding for the near-black body colour
- After `xcodegen generate`, SourceKit reports a spurious "No such module 'WhiteoutCore'"
  until the index rebuilds. The build is unaffected; ignore it
- Vercel MCP is authorized and ready for M3
