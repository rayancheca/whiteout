# State

**Updated:** Session 0006 · 2026-08-05
**Milestone:** M1 (Vertical Slice) — T-105 done; T-117 and T-118 opened

---

## Where the project is

**164 tests passing** across 24 suites in ~130 ms. iOS build green. Working tree clean.

A run now has an ending. T-105 is **done**: the skier crashes, slides to a stop, folds, and the
world falls back behind a summary card carrying distance, conditions, air time and flips. One
tap anywhere drops back in.

Before this session `RunScore` had existed and been unit-tested in Core since M0 and was
**never displayed anywhere**. `RunTelemetry.score(conditions:peak:)` was written and never
called. A crash produced a small HUD chip in the same position as the live readout, and nothing
about the screen said the run was over.

## The idea worth keeping (ADR-026)

**A settled crash is an exact fixed point of the simulation.** `coast` clamps with
`max(0, v - 9Δ)`, so once `velocityX` hits zero every field is a constant expression of itself
and `step(settled, any input, any delta) == settled`.

So **nothing is snapshotted.** A score read on any frame the card is visible is provably equal
to one read on the first — no latch to go stale, no distance ticking up under a motionless
skier, no score surviving a restart. That class of bug is unreachable rather than guarded.
`aSettledRunCannotDrift` holds the property and would catch a future `coast` that eased
asymptotically instead of clamping, which would silently make the summary never appear.

Run-end is a pure predicate: `hasCrashed && velocityX == 0 && collapse >= 0.9`. The only new
stored state in the whole change is `MountainScene.endReason`, naming which crash it was.
`restart()` gained one reset line.

## Numbers worth keeping

- **The beat is 0.23–1.18 s, median 0.60 s**, and scales with crash severity for free: a crash
  at 32 m/s slides 1.42 s, one at 10 m/s slides 0.44 s.
- `collapseFloor = 0.9` is reached in `ln(10)/Rate.crash` = 0.233 s. `Rate` is private, so a
  test pins the coupling rather than a comment claiming it.
- **A held tuck, driven to its crash on every surface:** ice / crust / wind slab crash at frame
  55–130 and 10–24 m; slush ~370 and ~85 m; packed ~700 and ~250 m; powder ~2,700 and ~950 m.
  Same input, sixty times the run, decided entirely by the snow. Powder is why
  `everySurfaceProducesAScoreableRun` needs a 4,000-frame budget rather than the suite default
  of 1,800 — it failed on exactly that first.

## Two things the crash was getting wrong, now fixed

- It printed **"CAUGHT AN EDGE" over blown landings too.** The answer was already in the two
  states either side of the crash frame: from the air it is a landing, from the ground it is
  the edge. Derived in the shape of `FeelModel.landingImpact`, so nothing is added to
  `SkierState`.
- **The next tap could dismiss the result before it appeared.** A crash almost always arrives
  with the finger still down holding the tuck. Restart now requires a settled run, so the slide
  is a natural debounce — while "restart is one tap" stays literally true anywhere on screen,
  including on the card, which never hit-tests.

## Verified on the simulator

- The summary card twice, on two palettes — Tokyo daylight slush, Chamonix night slush. The
  accent tracks the weather (`palette.skierRim`): warm cream on one, cool near-white on the other.
- **BLEW THE LANDING** derived correctly on a real run — the label the old build got wrong.
- Restart in one tap: card gone, HUD back, new run live at 59 m / 34 km/h.
- Determinism, incidentally: restart + hold from the drop-in on unchanged conditions crashed at
  exactly 134 m with 0.7 s air, twice.

## Not verified on the simulator

- **"CAUGHT AN EDGE" has never been seen on screen.** Both reachable origins resolved to slush
  or packed, where a held tuck meets a jump before instability fills, so every captured crash
  was a blown landing. Covered by test on both sides (`theHeadlineNamesWhichCrashItWas` and
  `bothKindsOfCrashHappenOnARealMountain`) but not photographed.
- **The tap-during-settle debounce.** Three lines of plain logic, but the window is under a
  second and no capture landed inside it. There is no App-layer test target.
- Whether the 0.23–1.18 s beat reads as considered or as lag. If it reads long, the honest lever
  is `coast`'s 9 m/s² deceleration, not a bolted-on timer.
- Reduced-motion path; Dynamic Type (the card uses fixed sizes, like every other view here).
- Still outstanding from earlier sessions: haptics and procedural audio (no taptic engine in the
  simulator, needs T-109), and landscape-right safe area.

## T-116 is now cheap to reproduce

Found while hunting a ground crash: **Reykjavík / Packed stalls at 38 m** — 0 km/h, EDGE meter
near empty, fully upright, identical after six seconds. An order of magnitude cheaper than the
894 m and 913 m cases from session 0005, and it happens within seconds of the drop-in. Start
there.

Not fixed, deliberately. But T-105 built the place it resolves to: a stall becomes a second
disjunct in `RunOutcome.hasSettled`, and `RunScore.endedInCrash` already carries the distinction
downstream. The summary correctly does not fire today, and the test comment says so explicitly
so it cannot later be misread as covering the case.

## Also recorded

**The crash is currently the game's quietest moment.** `FeelModel` shake measures 0.78–0.93 on
the frame before a lost edge and exactly 0 on the crash frame. The guard causing that is
*correct* — both terms model riding, and relaxing it makes a crashed body chatter as though
still on its edges — so the fix is a separate crash channel summed in `applyShake`. Written into
the code and onto T-106 so it does not get "fixed" the wrong way.

## Environment notes

Carried forward from session 0005, all still true:

- **A stalled run and a stale process photograph identically.** Check the readouts: a *stalled*
  run is 0 km/h with a near-empty EDGE meter, full opacity and an upright pose; a *crash* is now
  0 km/h behind a summary card; a stale process is anything else frozen. Relaunch with
  `xcrun simctl terminate/launch booted com.whiteout.game`.
- **A crashed run is no longer photographically fragile** — the summary is stable indefinitely,
  so a crash capture needs no concurrent-capture trick. Only *held-input* checks still do
  (ADR-023).
- `touch_path` sustains a touch. `dt_ms` on the *first* point is not a pre-delay.
- **Which snow state you get is not selectable.** Origins resolve to live weather, so hunting a
  specific crash type means taking what the day gives you. Tokyo and Chamonix both gave slush
  this session, Reykjavík gave packed.
- zsh `nomatch` aborts a `&&` chain: `rm -f foo_*.png` with no matches kills the rest.
- The build lands in `./build/Build/Products/Debug-iphonesimulator/Whiteout.app`, not DerivedData.
- `timeout` does not exist on macOS; use `gtimeout` or nothing.
- Screenshots need `sips -r -90`; device portrait, app landscape.
- Dev panel taps in device points (402 × 874): gear `(366, 776)`, Chamonix `(108, 749)`,
  Reykjavík `(71, 750)`, Tokyo `(35, 760)`, The Resort `(322, 747)`, Thin Air `(188, 738)`,
  mute `(56, 775)`. Miami is clipped off the bottom of the picker and is not tappable.
- **The expanded dev panel overlaps the summary card's column.** Dev-only scaffolding that will
  not ship, and the card takes no touches, so the pickers stay operable.

## Next

**T-116** is the strongest candidate: it now has both a cheap reproduction and somewhere to
resolve to, and it is the last thing that can leave a run with no ending.

**T-114** (`GameView` rebuilds the scene every body evaluation) is still small, real and
unblocked. **T-103**, **T-106**, **T-117** and **T-118** are unblocked and independent.
