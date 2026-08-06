# State

**Updated:** Session 0007 · 2026-08-06
**Milestone:** M1 (Vertical Slice) — T-116 done; T-119 opened

---

## Where the project is

**170 tests passing** across 24 suites in ~1.5 s. iOS build green. Working tree clean.

Every run now has an ending. T-116 is **done**: a skier who grinds to a halt on a counter-slope
gets a summary card reading **RAN OUT OF SPEED**, and one tap drops back in. Before this session
that skier sat motionless forever — no crash, no summary, no input able to restore momentum.

The suite runs ~1.5 s rather than ~130 ms now. `noRunCanSitAtADeadStop` walks 60 real descents
of 9,000 frames each; it is the whole cost, and it is the test that would catch this defect
coming back.

## The idea worth keeping (ADR-027)

**A stall is a fixed point, and the counter-slope is the exact condition for it** — not a
heuristic and not a timer. `stepGrounded` accelerates by `-gravity · sin(contactAngle)` and drag
vanishes at zero speed, so a stopped skier is driven by that one term. A non-negative contact
angle gives a non-positive acceleration, `max(0, …)` clamps it back, the distance does not
change, and so the angle is identical next frame. The state is its own successor.

```swift
!hasCrashed && isGrounded && velocityX == 0 && terrain.contactAngle(at: distanceM) >= 0
```

That is what makes it answerable on one frame with nothing stored — the same property that made
a settled crash unsnapshottable in ADR-026. The obvious "stopped for N seconds" would have
stored an instant, needed its own `restart()` reset, its own frame-rate story and its own
determinism test.

Instability cannot rescue a stall either: the build term scales with speed, so a *held tuck at a
standstill never crashes out*. That is why the bug survived to M1 — every test in the suite held
the tuck, and a held tuck crashes long before it can stall.

## Numbers worth keeping

- **The safe player is the one who gets stuck.** Split by input tape over 720 runs of 600 s:
  a held tuck stalls **0%** of the time (instability crashes it first), a mixed tape 6.2%, and
  **never tucking stalls 46.2%** — 111 of 240 runs. Across all tapes it is 8.7% (314 of 3,600).
  This is exactly why the defect survived to M1: every test in the suite held the tuck.
- **The earliest stall found is 17.8 m** (seed 14, ice, no tuck, 5.9 s in). The field report of
  38 m on Reykjavík/Packed was not the worst case.
- **Whether a run stalls is frame-rate independent**: at 1/120, 1/60, 1/30 and 1/20 the same
  sweep gives 59/62/63/60 stalls, and the first one lands at t = 55.43–55.45 s, x = 960.80–960.92 m.
- **The counter-slopes are in the terrain, not in rounding**: 3.6–6.8% of sampled metres rise,
  and packed/seed-17 has 428 contiguous uphill stretches in 20 km, the longest 58.25 m at a peak
  of 0.251 rad. The ridge octave does out-climb the −0.30 base gradient.
- **The contact angle at a stall is always strictly positive**, minimum +0.0093 over all 314
  (shallowest independently measured: +0.0190, a gravity term of −0.187 m/s²). A skier stops
  while *climbing*; never on a descent. This is why the predicate is safe.
- **`instability` cannot rescue a stall**: a held tuck at v = 0 with `instability = 0.999`, run
  20,000 frames at 1/20 — 1,000 s — ends at `0.999`, uncrashed. `speedFactor` is 0, so `build` is 0.
- **Monotone over 1.17 M post-stall frames**: 206 stalls, zero frames where the predicate went
  false again once true.
- **183 stalls probed with 20 s of alternating input at 1/20** — the coarsest delta the loop can
  deliver — moved the skier **0.0 m**. None escaped, none crashed.
- Stall distances cluster hard per seed (~390 m for seed 777, ~950 m for 17, ~1,960 m for 4,242):
  it is one specific wall on each mountain, not gradual attrition.

## The second half of the defect, which was not in the ticket

`touchesBegan` gated restart on `hasCrashed`. Ending a stall without touching that would have
shipped something **worse** than the soft-lock: a summary card no tap could dismiss, while the
same tap started a tuck underneath it. The gate is now `isRunOver`. The crash debounce survives
as its own clause — a stall needs no equivalent, since it can only be reached with the skier
already at a standstill, so there is no reflex tap in flight to swallow.

Also: `Reason.isCrash` is `false` for a stall, so `feedback.crash()` no longer fires on every run
ending. A haptic thump there would report an impact that never happened.

## Verified on the simulator

- **The exact 894 m stall from the session-0005 field report now resolves.** Dropped in on the
  offline fallback (powder, "UNKNOWN RANGE"), never touched the screen, watched it climb:
  80 → 53 → 24 km/h → stop at 894 m → card reading **RAN OUT OF SPEED · 894 m · on Powder ·
  The Resort · 0.0s AIR**.
- The skier stands **upright** behind the card, at full opacity — correct, there is no fold. The
  HUD faded, the veil came up.
- Restart in one tap: card gone, HUD back, new run live at 28 m / 40 km/h.

## Not verified on the simulator

- **A stall under a held finger.** Every capture used the no-tuck tape, because that is what
  stalls. The held case is covered by `aStalledRunCannotRestartItself` on both inputs at four
  deltas, but not photographed.
- Still outstanding from earlier sessions: **"CAUGHT AN EDGE" has never been seen on screen**;
  haptics and procedural audio (no taptic engine in the simulator, needs T-109); reduced-motion
  path; Dynamic Type; landscape-right safe area.

## How the tests were made to earn their place

Four mutations of the implementation, each run against the full suite:

| Mutation | Caught by |
|---|---|
| Drop the `contactAngle >= 0` clause | `aSkierStoppedOnADescendingSurfaceIsNotStalled` |
| Drop the stall disjunct (pre-T-116) | `aRunStalledOnACounterSlopeIsOver`, `aStallIsReportedAsARunThatDidNotCrash`, `noRunCanSitAtADeadStop` (20+ sites) |
| `isCrash` always true | `theStallNamesItselfAndIsNotACrash` |
| Drop the `isGrounded` clause | **nothing** — until `aMotionlessSkierInTheAirHasNotStalled` was added for it |

The fourth is the one worth remembering: the doc comment claimed a test pinned that clause and
none did. Written now, and it fails under the mutation.

## Also recorded

**`RunScore` needed no change at all.** `endedInCrash` reads `state.hasCrashed`, which is already
`false` for a stall — the previous session's guess that the distinction was already carried
downstream was exactly right. `aStallIsReportedAsARunThatDidNotCrash` pins it, because "needed no
change" is a claim the next person to touch `RunScore.from` will not otherwise know was
load-bearing.

**`RunTelemetry.finishedScore` is a second, parallel construction of `RunScore`.** The App never
calls `RunScore.from` — only the tests do. The two agree today only because `hasCrashed` is
mirrored verbatim at `RunTelemetry.swift:47`, so a change to one must land on both or neither.
Left alone deliberately: unifying them is not T-116, but it is a live trap.

**The crash is still the game's quietest moment** (carried forward, still on T-106): `FeelModel`
shake measures 0.78–0.93 on the frame before a lost edge and exactly 0 on the crash frame. The
guard causing it is *correct* — both terms model riding — so the fix is a separate crash channel
summed in `applyShake`, not a change to the guard.

## Environment notes

Carried forward, all still true:

- **A stalled run and a stale process no longer photograph identically** — a stall now ends in a
  card. A stale process is anything else frozen; relaunch with
  `xcrun simctl terminate/launch booted com.whiteout.game`.
- Location is denied on this simulator, so conditions resolve to **offline · default conditions**
  (powder, "UNKNOWN RANGE", The Resort). That path is a stall reproduction in its own right: drop
  in, touch nothing, wait ~90 s.
- Only *held-input* checks still need the concurrent-capture trick (ADR-023).
- `touch_path` sustains a touch. `dt_ms` on the *first* point is not a pre-delay.
- zsh `nomatch` aborts a `&&` chain: `rm -f foo_*.png` with no matches kills the rest.
- `swift test` must be run from `Core/`; the shell's cwd persists between commands.
- The build lands in `./build/Build/Products/Debug-iphonesimulator/Whiteout.app`, not DerivedData.
- `timeout` does not exist on macOS; use `gtimeout` or nothing.
- Dev panel taps in device points (402 × 874): gear `(366, 776)`, Chamonix `(108, 749)`,
  Reykjavík `(71, 750)`, Tokyo `(35, 760)`, The Resort `(322, 747)`, Thin Air `(188, 738)`,
  mute `(56, 775)`. Miami is clipped off the bottom of the picker and is not tappable.

## Next

**T-119** is the honest successor: T-116 made the stall legible, not rare. A card reading "17 m"
is a broken game, not a short run, and 8.7% of runs stall. The two candidate causes are already
measured and separable — the ridge octave locally out-climbing the base gradient, and a 8 m/s
drop-in that buys only 3.3 m of climb. Note it moves every distance in this file and every README
screenshot.

**T-114** (`GameView` rebuilds the scene every body evaluation) is still small, real and
unblocked. **T-103**, **T-106**, **T-117** and **T-118** are unblocked and independent.
