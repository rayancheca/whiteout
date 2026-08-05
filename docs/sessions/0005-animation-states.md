# Session 0005 — animation states and angle-space blending

**T-102 and T-111 closed together. T-116 opened. ADR-023 amended.**
Tests 111 → 143. Green throughout.

## Commits

- `c20d636` feat: skier animation states and angle-space rig blending (T-102, T-111)
- this log

## Why the two tasks were one

The handoff suggested pairing them because T-102 would introduce the intermediate blend values
that make T-111's bone shortening visible. That turned out to be not just convenient but
causal, and worth stating precisely:

`FeelModel` emitted `tuckCompression` as a binary 0 or 1, and `SkierRig.pose` hard-switched
between four authored poses. **No intermediate blend value was ever drawn.** That is why
T-111's defect had been unobservable since T-101 — not because it was subtle, but because the
code path that exhibits it never executed. Adding transitions is what made the defect
reachable; fixing the blend is what made the transitions correct. Doing either alone would
have shipped something visibly wrong.

## What was built

**Angle-space blending (ADR-024).** `RigAngles` — the joint angles — is now canonical, and
`SkierPose` is what falls out of solving it. Bone lengths became constants of the solver, so
they are rigid at every `t` by construction rather than by tolerance.

`SkierPose.blended(toward:amount:)` and `RigPoint.blended` were **deleted rather than
deprecated**. The type-level half of the fix matters as much as the maths: a pose that carries
no blend method cannot be blended wrongly by the next caller.

**Shortest-arc interpolation, and the proof case.** The pole sits at −2.406 rad upright and
+2.898 tucked. Both trail behind the skier; numerically they are 5.3 rad apart, so a plain
lerp sweeps the pole *forward through the skier's chest* and back. The −0.98 rad short arc
swings it the way a pole actually swings. Position blending had concealed this by shortening
the pole instead of rotating it the long way — the two bugs were hiding each other.

**Transition state (ADR-025).** `SkierAnimator`, an immutable struct of five `0...1` weights
that `MountainScene` carries between frames. It reads state and cues and writes to neither, so
replay is untouched. Composing weights rather than running a state machine lets transitions
overlap — landing while still tucked, crashing mid-flip — without enumerating the pairs.

**Four new poses:** `carveLeft` / `carveRight` (the flex-and-extend halves of an edge change),
`flipTuck`, `landing`. Carve is driven by `distanceM` rather than a clock: no memory needed,
speeds up with the skier for free, identical on replay at any frame rate.

## What broke, and what measurement caught

**The first rate pass was too fast.** `tuckIn = 17` moved the weight 25% in a single frame,
which swept the head 5.2 points and the pole tip 6.6 at a 30-point body — that reads as a cut,
not a fold. Softened to 12 (head 4.0 pt). This was only findable by *measuring per-frame joint
travel*, not by looking at endpoint values or at the poses. Every joint now holds 3.2–6.4×
headroom below what a single-frame switch would move it.

**The first carve amplitude was invisible.** It measured fine — a 6.7% silhouette bob — and
was about 2 points on screen. Doubled it, and more importantly leaned on the *pole* rather
than the body: the tip swings ~10 points against the body's 3, because it is a long lever.
The lesson generalises: at this figure size, angular change on a long segment reads far better
than positional change on the torso.

**A test assertion was wrong, not the code.** "A softer landing mid-recovery does not deepen
the absorption" was written as a threshold (`> 0.8`) that failed at 0.70 — two frames of decay
had already taken it there. The honest form is to run the sequence with and without the second
impact and assert the frames are *identical*; the threshold version would have passed for the
wrong reason.

**A contrast test was wrong-headed.** "Budget < half a hard switch" was first written against
`upright → tuck`, which happens to leave the boot exactly where it was, making the assertion
unsatisfiable. Fixed to use the worst snap across all 56 authored pairs.

## T-116 — a run can stall to a dead stop

Found by running, not by reasoning. The skier loses all speed on a flat and sits at **0 km/h
indefinitely**: no crash, no summary, no input that can restore momentum. Reproduced at 894 m
and at 913 m. Pre-existing simulation behaviour, untouched by this session.

**This corrects ADR-023.** That ADR attributed session 0003's "frozen at 894 m / 0 km/h" to a
stale process. Session 0005 reproduced a dead stop at *exactly 894 m* on a freshly launched,
demonstrably live app. The terrain is deterministic, so a run that always dies in the same
place is the simulation stalling, not a process freezing. ADR-023's conclusion stands — the
tuck renders, concurrent capture is still mandatory — but the diagnostic needed a third
branch, added as an amendment.

The general lesson is uncomfortable and worth keeping: **session 0003 mis-measured, session
0004 correctly identified that 0003 had mis-measured and then mis-attributed the cause.** Two
consecutive sessions produced confident, well-argued, partly-wrong diagnoses of the same
screenshot. The thing that finally settled it was reproducing the number on a known-live app.

## Verification, honestly

**Seen on screen:** upright, a *mid-transition* frame (the first that could exist — every limb
full length and connected, pole correctly swept behind), full tuck, 46 frames of carve rhythm,
and a stationary skier holding exact `upright` with no sway.

**Never seen on screen:** air, flip, landing absorption, crash collapse. Roughly 100
screenshots across six attempts; the touch never overlapped a jump. Covered headlessly instead
by `SkierAnimatorRunTests`, which drives the *real* simulation over generated terrain — seed
17 reaches air 1.00, flip 1.00, landing 1.00, crash 1.00, with rigidity and joint continuity
asserted on every frame of six descents across all six snow states.

The final rate softening is test-verified only; the on-screen captures predate it. Only six
easing constants changed — poses, blend maths and composition order are byte-identical.

## Environment lessons

- **Two identical captures no longer prove a stale process.** A stalled run is 0 km/h with a
  near-empty EDGE meter, full opacity, upright pose. A crash is 0 km/h with a full meter, 75%
  alpha, collapsed pose. Check before concluding.
- **`dt_ms` on the first `touch_path` point is not a pre-delay.** Scheduling a hold to begin
  later that way does not work. Landing a touch inside a capture window succeeded twice in
  eight attempts; backgrounding the capture loop and issuing the touch in the same tool batch
  was the only thing that worked at all.
- **zsh `nomatch` aborts a `&&` chain.** `rm -f foo_*.png` with no matches killed an entire
  capture run silently.
- **The skier's screen x shifts right with speed** (`cameraLead`), so a fixed crop window
  loses it. Locate it as the darkest pixel cluster below the conditions card.
- ImageMagick and PIL are both present; `montage` fails on font lookup, so build contact
  sheets with PIL.

## Left undone deliberately

- README screenshots were **not** recaptured. The eight beats from session 0004 remain
  accurate — the `tuck` and `collapsed` poses are byte-identical to before, and the gliding
  beats now show a valid point in the carve cycle, so nothing shows a state the build cannot
  produce (ADR-022). The mid-transition capture would make a striking ninth beat; that is a
  future call, not a blocker.
- T-114 remains open. It was session 0003's prime suspect and is still small and real.
