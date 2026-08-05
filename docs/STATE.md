# State

**Updated:** Session 0005 · 2026-08-05
**Milestone:** M1 (Vertical Slice) — T-102 and T-111 done together, T-116 opened

---

## Where the project is

**143 tests passing** across 22 suites in ~70 ms. iOS build green. Working tree clean,
**11 commits ahead of `origin/main` and not yet pushed**.

T-102 and T-111 are **done**, and they were the same fix. The rig now blends in angle space
and carries transition state between frames, so the skier moves between poses instead of
switching between them.

## Why the two tasks were one

`FeelModel` emitted `tuckCompression` as a binary 0 or 1, and `SkierRig.pose` hard-switched
between four authored poses. So no intermediate blend value was ever drawn — which is exactly
why T-111's bone shortening had been unobservable since T-101. Adding transitions is what
made the defect visible; fixing the blend is what made the transitions correct.

## What changed

**Angle-space blending (ADR-024).** `RigAngles` — the joint angles — is now canonical, and
`SkierPose` is what falls out of solving it. Blending happens on angles; bone lengths are
constants of the solver, so they are rigid at every `t` by construction. `SkierPose.blended`
and `RigPoint.blended` are **deleted**, not deprecated: a pose that carries no blend method
cannot be blended wrongly by the next caller.

Interpolation takes the **shortest arc**, and the pole is the proof. It sits at −2.406 rad
upright and +2.898 tucked — both trailing behind the skier, but 5.3 rad apart numerically. A
plain lerp sweeps it *forward through the skier's chest*; the −0.98 rad short arc swings it
the way a pole swings. Position blending had concealed this by shortening the pole instead.

**Transition state (ADR-025).** `SkierAnimator` is an immutable struct of five `0...1` weights
that `MountainScene` carries and advances each frame. Composing weights rather than running a
state machine lets transitions overlap — landing while still tucked, crashing mid-flip —
without enumerating the pairs.

**Four new poses:** `carveLeft` / `carveRight` (the flex-and-extend halves of an edge change),
`flipTuck` (knees to chest while rotating hard), `landing` (absorption on touchdown).

The carve rhythm is driven by `distanceM`, not a clock: no memory needed, speeds up with the
skier for free, identical on replay at any frame rate.

## Numbers worth keeping

- Transition rates were set against **measured per-frame joint travel**, not by feel. At
  `tuckIn = 17` the head crossed 5.2 points in one frame at a 30-point body — that reads as a
  cut, not a fold. At 12 it is 4.0, and every joint holds 3.2–6.4× headroom below what a
  single-frame switch would move it.
- The carve pair spans only 10% of body height, but the pole tip travels ~10 points against
  the body's 3. A first pass at half these amplitudes measured fine and was invisible on
  screen.
- Widest shortest-arc separation in the rig is the pole between `carveRight` and `flipTuck`
  at 1.49 rad — 1.65 rad of headroom below π, where shortest-arc would start picking the
  wrong side. A test asserts that margin.

## Verified on the simulator

Three genuinely distinct shapes captured on a live app, including a **mid-transition frame**
— the first one that could exist, and the T-111 proof: every limb full length and connected,
pole correctly swept behind. Also 46 frames of the carve rhythm (flexion, extension, pole
swing), and a stationary skier holding exact `upright` with no sway.

## Not verified on the simulator

**Air, flip, landing absorption and crash collapse were never captured on screen.** Roughly
100 screenshots across six attempts; the touch never overlapped a jump. They are covered
headlessly instead, by `SkierAnimatorRunTests` driving the *real* simulation over generated
terrain — seed 17 reaches air 1.00, flip 1.00, landing 1.00 and crash 1.00, with bone rigidity
and joint continuity asserted on every frame of six descents across all six snow states.

The final rate softening was verified by test only; the on-screen captures predate it. Only
six easing constants changed — poses, blend maths and composition order are byte-identical.

Also still unverified from earlier sessions: haptics and procedural audio (no taptic engine in
the simulator, needs T-109), and landscape-right safe area.

## T-116 — a run can stall to a dead stop (new, open)

Found while verifying. The skier loses all speed on a flat and sits at **0 km/h indefinitely**:
no crash, no summary, and no input that can restore momentum. Reproduced at 894 m and 913 m.
Pre-existing simulation behaviour, untouched by this session.

**This corrects ADR-023.** That ADR blamed Session 0003's "frozen at 894 m / 0 km/h" on a
stale process. Session 0005 reproduced a dead stop at *exactly 894 m* on a freshly launched,
demonstrably live app — and since the terrain is deterministic, a run that always dies at the
same place is the simulation stalling, not a process freezing. ADR-023's conclusion still
stands (the tuck renders; concurrent capture is still mandatory), but the diagnostic now needs
a third branch — see the amendment in `DECISIONS.md`.

## Environment notes

- **Two identical captures no longer prove a stale process.** Check the readouts: a *stalled*
  run is 0 km/h with a near-empty EDGE meter, full opacity and an upright pose; a *crash* is
  0 km/h with a full meter, 75% alpha and the collapsed pose; a stale process is anything else
  frozen. Relaunch with `xcrun simctl terminate/launch booted com.whiteout.game`.
- **`touch_path` sustains a touch**, but landing it inside a capture window is unreliable —
  it succeeded twice in eight attempts this session. `dt_ms` on the *first* point is **not** a
  pre-delay; scheduling a hold to start later that way does not work. Best results came from
  backgrounding the capture loop and issuing the touch in the same tool batch.
- **zsh `nomatch` will abort a `&&` chain**: `rm -f foo_*.png` with no matches kills the rest
  of the command. Cost one silent no-op capture run this session.
- The build lands in `./build/Build/Products/Debug-iphonesimulator/Whiteout.app`
  (`verify.sh` passes `-derivedDataPath build`), **not** DerivedData.
- **`timeout` does not exist on macOS.** Use `gtimeout` or no wrapper.
- Screenshots need `sips -r -90`; device portrait, app landscape. ImageMagick and Python PIL
  are both available; `montage` fails on font lookup, so build contact sheets with PIL.
- The skier's screen x **shifts right with speed** (`cameraLead`), so a fixed crop window will
  lose it. Locate it as the darkest pixel cluster below the conditions card.
- Dev panel taps in device points (402 × 874): gear `(366, 776)`, Chamonix `(108, 749)`,
  Reykjavík `(71, 750)`, Tokyo `(35, 760)`, The Resort `(322, 747)`, Thin Air `(188, 738)`,
  mute `(56, 775)`. Miami is clipped off the bottom of the picker and is not tappable.
- A cold launch can resolve to `offline · default conditions`; re-selecting an origin in the
  dev panel forces a live re-resolve.

## Next

**T-105 (crash + run-summary flow)** is now unblocked by T-102 and is the natural follow-on —
it also gives T-116 somewhere to resolve to, since a stalled run needs the same summary a
crashed one does.

**T-114** (`GameView` rebuilds the scene every body evaluation) is still small, real and
unblocked. **T-103** and **T-106** remain unblocked and independent.
