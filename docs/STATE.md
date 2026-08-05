# State

**Updated:** Session 0003 · 2026-08-05
**Milestone:** M1 (Vertical Slice) — T-112 attempted, blocked on a bug it uncovered

---

## Where the project is

**111 tests passing** across 16 suites in ~30 ms. iOS build green. No source changed this
session — the code is exactly as Session 0002 left it.

T-112 (refresh README screenshots) was attempted and is **blocked**. Four of the eight
beats are captured and good; the rest need a tuck to photograph, and the tuck does not
render. That is now **T-113**, and it is the most important thing in the project.

## The bug that stopped the session

**Holding the screen produces no visible change.** The game has exactly one input, and it
currently does nothing you can see.

What is established, with evidence:

- The **render path is fine.** The `collapsed` crash pose renders correctly — photographed,
  lying flat on the slope. It reaches the screen through the identical
  `SkierRig.pose(for:cues:)` → `SkierNode.apply(_:)` call that the tuck would use. So pose
  switching works end to end for a non-upright pose.
- The **rig is fine.** `tuckCompression` is binary (`FeelModel.swift:56`), so a held tuck
  is `upright.blended(toward: tuck, amount: 1)` — the tuck pose exactly. A Core test already
  asserts this ("a held tuck reaches the tuck pose exactly").
- Therefore the fault is **`isHolding` never staying true.** It is set in `touchesBegan`
  and cleared only in `touchesEnded` / `touchesCancelled` / `restart`
  (`MountainScene.swift:106–125`). Something ends the touch immediately.
- Corroborating from the physics side: **speed does not rise across a hold.** Measured
  61 → 63 km/h over a 15 s press, which is drift, not a drag reduction.

Root cause is **not** yet identified. Leading suspect: `GameView.swift:39` passes
`makeScene(size:)` — a freshly constructed `MountainScene` — as `SpriteView`'s scene on
every body evaluation. `.id(sceneID)` pins the *view* identity but not the scene value, and
a re-presented scene would cancel an in-flight touch and lose the flag. Unproven.

**Open question only a human can answer:** when a person presses and holds on the simulator,
does the skier change shape? If no, the app is broken. If yes, it was synthetic input
failing and T-113 is much narrower. The user reported the game "does nothing", which points
at the first, but it was not confirmed as a direct answer to this question.

## Verified working this session

Confirmed by capture, not by reasoning:

- **The night palette renders.** Tokyo at 03:05 local resolves to a dark sky with stars at
  5,200 m. Session 0002 listed this as never having been looked at.
- **The crash pose lies flat on the slope.** Photographed at the end of a Reykjavík run —
  collapsed sprawl, correct surface angle, EDGE meter full red. Also previously unverified.
- **Fullscreen and the rig hold up.** Every capture is edge to edge at 2622 × 1206 px, and
  the skier reads as a jointed figure — head, torso, arms, poles, ski — at run scale.
- **Live Open-Meteo still drives everything.** Four cities resolved to four genuinely
  different snowpacks within one session (see below).

## The four captures

In `docs/screenshots/pending/`, not yet in the README. All fullscreen, live data, real rig.

| Beat | Origin | Result |
|------|--------|--------|
| 1 | Chamonix | Spring Slush · 10° · 8 km/h · 17 km |
| 2 | Reykjavík | Boilerplate · −6° · 35 km/h · 25 km |
| 3 | Tokyo @ 2,800 m | Spring Slush · 6° · 3 km · night |
| 4 | Tokyo @ 5,200 m | Boilerplate · −10° · 3 km · stars |

Beats 3 and 4 are the strongest pairing the project has produced: identical weather and
moment, 2,400 m apart, 16 °C colder, slush becomes boilerplate. Reykjavík is a better story
than the old capture too — 35 km/h wind is *why* it is scoured.

Per ADR-021 these use named cities, never the real device location, because the repository
is public and the conditions card is a location disclosure.

## Still unverified

- **Haptics and procedural audio.** No taptic engine in the simulator. Needs T-109.
- **Landscape-right safe area.** Landscape-left only, still.
- **Mid-blend bone rigidity.** `blended(toward:amount:)` shortens bones at intermediate `t`
  (~6.6% of torso length at 0.5). That is T-111. Note this is currently *unobservable* —
  with `tuckCompression` binary and the tuck not rendering, no intermediate `t` is ever
  drawn on screen.

## Environment notes

Corrections to Session 0002's notes, learned expensively:

- **`timeout` does not exist on macOS.** `timeout 45 xcrun simctl …` fails as
  command-not-found and, wrapped in `|| echo FAILED`, reads exactly like the command
  failing. This cost most of an hour of misdiagnosis. Use `gtimeout` or no wrapper.
- **Neither `touch_path` nor `tap` with `duration` sustains a touch.** Both deliver
  touch-down and touch-up effectively back to back. A plain tap *does* reach the scene —
  it restarts a crashed run — so touch delivery works; duration does not.
- **`xcrun simctl io … screenshot` needs Simulator.app actually running** and the device
  booted, or it returns "Timeout waiting for screen surfaces".
- The in-app simulator panel (`attach`) streams the device without controlling the Mac and
  coexists fine with `simctl` screenshots. **Use it. Do not reach for desktop control** —
  it was tried this session, it did not solve the problem, and the user objected to it.
- Screenshots still need `sips -r -90`; device portrait, app landscape.
- Skier ink thresholds below luminance 35; terrain starts at 40. Exclude the leftmost
  200 px in landscape or the Dynamic Island is picked up as body.

## Next

**T-113 — make a held input sustain the tuck.** Answer the human question above first, then
instrument `isHolding` and confirm what ends the touch. T-112 unblocks the moment the tuck
renders; four of its eight beats are already shot.

T-102, T-103 and T-106 remain unblocked and independent, but T-113 should come first — it
is the difference between a game that responds and one that does not.
