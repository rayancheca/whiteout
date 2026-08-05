# Session 0002 — Skier rig and fullscreen

**Date:** 2026-08-05 · **Milestone:** M1 · **Outcome:** T-101 and T-110 done, 111 tests

## Built

- **T-110 — fullscreen + safe area.** `INFOPLIST_KEY_UILaunchScreen_Generation`, canvas
  edge-to-edge, overlays inset to the real insets.
- **T-101 — skier art + rig.** `SkierRig` in `WhiteoutCore`: a normalised skeleton built
  from one bone table, four poses (`upright`, `tuck`, `airborne`, `collapsed`), and a pure
  `pose(for:cues:)`. `SkierNode` in `App/` renders it as two stroke passes per width class
  plus a filled head. `skierBody`/`skierRim` added to `ScenePalette`; ridge-band colours
  moved into Core so the legibility test can compute the skier's actual backdrop.
- 85 → 111 tests, 13 → 16 suites, still ~30 ms.

## Bugs found by measuring, not reasoning

The Session 0001 pattern held. None of these were visible by reading code.

1. **The app had never been fullscreen.** No `UILaunchScreen` key, so iOS ran it in legacy
   compatibility mode: measured **564 × 376 pt inside an 874 × 402 pt display** — 36% of the
   width was black bars. No line of source was wrong; the bug lived in the *absence* of a
   plist key, which is why it survived all of M0. See ADR-017.

2. **The skier was invisible at night.** Measured against the real generator, the old fill
   separated from its backdrop by **0.006 Oklab L** — about one 8-bit code value. Two tones
   pinned to opposite ends of the lightness axis now, spread ≥ 0.60. See ADR-019.

3. **The legibility test passed while testing the wrong backdrop.** The first version
   asserted contrast against `skyHorizon`/`skyZenith` and went green — but the skier needs
   ~111 m of relative altitude to reach sky and never does. It is drawn against the nearest
   parallax ridge band the entire run, whose lightness sits mid-axis, which is why no single
   tone can work. A green test on the wrong subject is worse than no test: it retires the
   question.

4. **A tolerance band is not a rigidity check.** `limbsStayAttached` allowed each limb
   0.05–0.32 and passed while the upper arm was **51% shorter** in the tuck than standing and
   the forearm **67% longer**. That is what made the arms read as a blob on screen. Poses are
   now built by walking one bone table, so rigidity is structural, and the test compares every
   pose against the standing one.

5. **The drawn ski could not lie on the snow.** The rendered skier is ~9× life size, so its
   34.5 pt ski spans **17 m** of terrain while physics computes contact over 1.7 m. Rendering
   now takes the surface angle over the length it actually draws. The capsule hid this by
   having no long horizontal element. See ADR-020.

6. **A claimed fix that did nothing.** `contactPoint(for:)` returned `pose.boot`, which is
   `(0, 0.030)` in every pose — so "spray from the skis" moved the emitter 0.9 pt. Replaced
   with `sprayOrigin(for:)` at the ski tail, now visibly trailing.

7. **The opening frame drew a head and nothing else.** `buildSkier` never posed the node and
   `update` returns early on its first call, so every limb path was nil and the head sat at
   the node origin.

8. **A crash could render head-down.** The simulation freezes `rotation` at impact, so a
   botched backflip slid to a halt at 126°.

9. **`restart()` left the previous run behind it.** The trail is keyed by distance, so its
   points survived a reset to zero and would reappear as a stray line.

## On the design workflow

A six-agent design workflow ran in parallel with implementation. Its value was uneven and
worth recording honestly.

**What it got right and I had wrong:** finding #3 above. The claim that the skier's backdrop
is the near ridge rather than the sky came from an agent reading the scene's own layout
arithmetic, and it reframed the colour problem entirely. Finding #4 and #6 also came from its
adversarial pass.

**What it got wrong:** its merged brief was calibrated against a baseline that had already
moved, and would have reverted ADR-020, set `headRadius` back to 0.085 while *shrinking* the
torso — reintroducing the lollipop the code documents as already tried — and more than
doubled the rim width at night. Its own critique agents caught this.

**Lesson:** a review is worth running even when most of its output is discardable, but only
if every finding is verified against the source before acting. Three of its claims were
confirmed by measurement and fixed; three would have caused regressions.

## Measured

- Content: 564 × 376 → **874 × 402 pt**, 100% coverage.
- Skier silhouette on screen: **32.0 pt upright, 16.7 pt tucked** — ratio 0.52, against the
  placeholder's fake 0.68 vertical squash.
- Palette sweep, `snowShadow.l` 0.370 (night) → 0.640 (alpine noon); `skyHorizon.l` 0.150 →
  0.900; near ridge 0.249 → 0.590.

## Not verified

- Haptics and procedural audio — still no taptic engine in the simulator (T-109).
- Landscape-right safe area — only landscape-left was seen.
- The night palette on screen — guaranteed by test across 8 palettes, never looked at.
- The crash pose and the opening frame — correct by construction, not photographed. Packed
  snow has too little chatter to crash within a test run.

## Left undone

README screenshots are stale: all 7 show the letterboxed frame and the capsule, and caption
6 describes the deleted squash. Recorded as T-112; the push is held until they are refreshed
rather than publishing captures that misrepresent the app.
