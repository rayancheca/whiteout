# Session 0006 — the crash + run-summary flow

**T-105 closed. T-116 reproduced far cheaper. ADR-026 recorded. T-117 and T-118 opened.**
Tests 143 → 164. Green throughout.

## What was built

A finished run now has an ending. Before this session a crash produced a small HUD chip —
`CAUGHT AN EDGE / tap to drop in again` — in the same screen position as the live readout, and
nothing else. `RunScore` had been implemented and unit-tested in Core since M0 and was **never
displayed anywhere**; `RunTelemetry.score(conditions:peak:)` existed and was never called.

Now the skier crashes, slides to a stop, folds, and the world falls back behind a summary card
carrying the distance, the conditions, the air time and the flips. One tap anywhere drops back
in.

## The spine: a settled crash is a fixed point

The design question was where to keep the finished run's score. The obvious answer — snapshot
it at the crash — turned out to be unnecessary, and the reason is worth keeping.

`coast` computes `velocityX = max(0, v - 9Δ)` and advances distance by `velocityX · Δ`. Once
`velocityX` reaches zero, every field of the state is a constant expression of itself, so
`step(settled, any input, any delta) == settled` exactly. A score read on any frame the card
is visible is *provably* identical to one read on the first.

So nothing is snapshotted. There is no latch to go stale, no distance ticking up under a
motionless skier, no score surviving into the next run — that whole class of bug is unreachable
rather than guarded. `aSettledRunCannotDrift` is what holds the property, and it is what would
catch a future `coast` that eased asymptotically instead of clamping, which would silently make
the summary never appear at all.

Run-end is therefore a pure predicate over two values the scene already carries:

```
hasSettled = hasCrashed && velocityX == 0 && collapse >= 0.9
```

The only new stored state anywhere in the change is `MountainScene.endReason`, which exists
solely to name *which* crash it was. `restart()` gained exactly one reset line.

## The beat is two clocks that already existed

The pause between the crash and the card is the slide plus the fold. Both were already in the
frame and already cleared by `restart()`; a third clock would have needed its own reset entry,
its own frame-rate story and its own determinism test.

Measured, it runs **0.23–1.18 s, median 0.60 s** — and it scales with the severity of the crash
for free, because a faster crash slides further. A crash at 32 m/s takes 1.42 s to stop; one at
10 m/s takes 0.44 s.

The collapse term is what covers the other end. A crash entered at walking pace stops in two or
three frames, and gating on the stop alone would drop the card over a skier still standing
upright. `collapseFloor = 0.9` is reached in `ln(10)/Rate.crash` = 0.233 s. `Rate` is private to
the animator, so a test pins that coupling rather than a comment asserting it.

## Two things the crash was getting wrong

**It was printing the wrong cause.** "CAUGHT AN EDGE" was shown over blown landings too. The
honest answer already existed in the two states either side of the crash frame: entered from the
air it is a landing the skier failed to ride out, entered from the ground it is the edge letting
go. `RunOutcome.reason(previous:current:)` derives it in the same shape as
`FeelModel.landingImpact` — an event from a state comparison, so nothing is added to `SkierState`
and the tape a server re-simulates is untouched. Both on-screen captures this session read
**BLEW THE LANDING**, which the old build would have mislabelled.

**The next tap could dismiss the result before it appeared.** A crash almost always arrives with
the finger still down holding the tuck, so the very next touch is reflex rather than intent.
Restart now requires a *settled* run, which makes the slide a natural debounce — while leaving
"restart is one tap" literally true anywhere on screen, including on the card, which never
hit-tests.

## The card

Trailing side, vertically centred, 300 pt wide. It sits opposite the skier, who is at 0.34 of
the width — the collapsed body is the other half of the story and should not be covered by the
thing describing it.

The distance is the hero at 64 pt, a little over twice the conditions card's headline. That
scale contrast is what stops the card reading as one more HUD chip. It is deliberately *not*
monospaced, unlike the live readout: those digits tick, these are settled.

The accent is `palette.skierRim` — the one tone in the palette pinned for legibility in every
weather, unbound by exposure and climbing further above the snow as the scene darkens. So the
number belongs to the day exactly as the skier does: warm cream on the Tokyo capture, cool
near-white on the Chamonix night one.

The scrim is `0.18 + 0.22 · exposure`. The same veil that separates a card from a night sky
would be a dirty smear over a lit whiteout.

## What weather does to a run, measured

Driving a held tuck to its crash on every surface produced the sharpest demonstration yet of
invariant 5:

| Surface | Crash at | Distance |
|---|---|---|
| ice / crust / wind slab | frame 55–130 | 10–24 m |
| slush | frame ~370 | ~85 m |
| packed | frame ~700 | ~250 m |
| powder | frame ~2 700 | ~950 m |

Same input, sixty times the run, decided entirely by the day's snow. This also cost a test
failure first: `everySurfaceProducesAScoreableRun` was written against the suite's default
1,800-frame budget, and powder needs 4,000. The blueprint's claim that a held tuck crashes on
every surface had been extrapolated from a `.packed`-only test.

## T-116 reproduced at 38 m

While hunting for a ground crash on Reykjavík / Packed, the run stalled: **38 m, 0 km/h, EDGE
meter near empty, fully upright, identical after six seconds.** That is an order of magnitude
cheaper to reach than the 894 m and 913 m cases from session 0005, and it happens within seconds
of the drop-in. A future session should start there.

Not fixed — it is T-116 and widening T-105 to absorb it is exactly what the mid-session protocol
forbids. But T-105 built the place it resolves to: a stall becomes a second disjunct in
`hasSettled`, and `RunScore.endedInCrash` already carries the distinction downstream. The
summary correctly does *not* fire today, and `everySurfaceProducesAScoreableRun` says so in a
comment so it cannot be misread as covering the case.

## Verified on the simulator

- The summary card, twice, on two palettes — Tokyo daylight slush and Chamonix night slush.
- **BLEW THE LANDING** derived correctly on a real run.
- Restart in one tap: card gone, HUD back, new run live at 59 m / 34 km/h.
- Determinism, incidentally: restarting and holding from the drop-in on unchanged conditions
  crashed at exactly 134 m with 0.7 s of air, twice.
- The dev panel expanded overlaps the card's column. Dev-only scaffolding that will not ship,
  and the card takes no touches, so the pickers stay operable.

## Not verified on the simulator

- **CAUGHT AN EDGE has not been seen on screen.** Both reachable origins gave slush or packed,
  where a held tuck meets a jump before instability fills, so every crash captured was a blown
  landing. Covered by test on both sides — `theHeadlineNamesWhichCrashItWas` asserts the
  derivation and `bothKindsOfCrashHappenOnARealMountain` proves both occur on real descents —
  but not photographed.
- **The crash haptic.** `feedback.crash()` is unchanged and remains unverifiable in the
  simulator; still needs T-109.
- **Whether the 0.23–1.18 s beat reads as considered or as lag.** The range is arithmetic. If it
  reads long, the honest lever is `coast`'s 9 m/s² deceleration, not a bolted-on timer.
- **The tap-during-settle debounce.** Three lines whose logic is plain, but the window is under
  a second and no capture landed inside it. There is no App-layer test target.
- Reduced-motion path, and Dynamic Type (the card uses fixed sizes like every other view here).

## What the review pass changed

An adversarial review ran mutation tests against the suite and found four assertions that could
not fail. All are fixed; the interesting part is *why* each was hollow.

- **`hasSettled`'s `hasCrashed` clause was pinned by nothing.** Deleting it left all 163 tests
  green. Every fixture that stopped had also crashed, and on a real descent the collapse weight
  only exceeds 0.9 after 0.23 s of `hasCrashed` being true — so the collapse term masked it
  completely. This is the exact clause keeping T-116 out of scope, and the next person to touch
  this predicate is by design the T-116 implementer. Now pinned by
  `aRunThatNeverCrashedIsNeverOver`, using a stalled state modelled on the real 894 m reading.
  Re-verified by mutation: removing the clause now fails exactly that one test.
- **`aSettledRunCannotDrift` could not catch the failure its own comment claimed.** The fixture
  started at `velocityX: 0`, and zero is a fixed point of *any* decay — including the
  multiplicative one the comment said it guarded against. It now coasts down from 12 m/s and
  asserts the slide actually reaches a dead stop before testing the fixed point.
- **Both frame-rate tests passed on runs that never ended.** `elapsed < 5` was a loop bail-out,
  not an assertion, so two runs that both timed out agreed to within a frame and reported
  perfect frame-rate independence. They now return `nil` on timeout and fail loudly.
- **`theEndingNeverWritesToTheSimulation` was tautological.** It asked its question after the
  descent had already completed, so it could not observe a side effect on that descent and was
  only re-testing determinism. The two loops are now interleaved.
- **Swapping the two headline strings left the suite green** — the tests checked the enum case
  but never the rendered text, which is the thing the player actually reads and the thing the
  old build got wrong. Now asserted.

Three smaller App-layer fixes came out of the same pass: `ConditionsCard` was hit-testable and
would have swallowed the dismissing tap (making "one tap anywhere" false); `RunHUD` faded to
`.opacity(0)` stayed in the accessibility tree, so VoiceOver still read a stale `0m · 0 km/h`
behind the summary; and `telemetry` outlives the scene, so a conditions change left the previous
run's summary on screen over the opening frames of the new run — `didMove` now publishes.

`RunTelemetry` also went to guarded writes on every field. `@Observable` fires on assignment
rather than on change, so the card was being invalidated sixty times a second while showing a
run in which, by ADR-026, nothing can move.

## Also recorded

**The crash is the game's quietest moment.** `FeelModel` shake measures 0.78–0.93 on the frame
before a lost edge and exactly 0 on the crash frame. The guard causing it is *correct* — both
shake terms model riding, and relaxing it makes a crashed body chatter as though still on its
edges — so the fix is a separate crash channel in `applyShake`. Written into the code and onto
T-106 so the next session does not "fix" it the wrong way.

**T-117** — `MountainScene` is ~760 lines against a ~400 house limit.
**T-118** — `touchesEnded` drops the tuck when *any* finger lifts, even with another still down.
