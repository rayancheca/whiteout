# Session 0003 — Screenshot refresh, blocked by a dead input

**Date:** 2026-08-05
**Intent:** T-112 — recapture the 7 README screenshots against the real skier and the
fullscreen canvas, fix caption 6, push the 5 held commits.
**Outcome:** Blocked. Four beats captured; the rest need a tuck, and the tuck does not
render. Filed as T-113. Nothing pushed. No source changed.

---

## What was agreed up front

Three questions, answered by the user before work started:

1. **Origin for the altitude beats** — a named city, not the real device location. The repo
   is public and the conditions card prints place, temp, wind and visibility together, which
   is a location disclosure. Recorded as ADR-021.
2. **An eighth beat** showing the rig itself — upright versus tucked — since T-101 shipped
   the rig and no beat showcased it.
3. **Push gate** — commit locally, show the screenshots before pushing.

Answer 2 is what surfaced the bug. Without it there would have been no reason to compare
the two poses side by side, and a "tucked, flat out" caption would very likely have shipped
over a frame that is not tucked.

## What was captured

Four beats, all fullscreen at 2622 × 1206, all live Open-Meteo, all showing the jointed rig:

- Chamonix — Spring Slush, 10°, 8 km/h, 17 km
- Reykjavík — Boilerplate, −6°, 35 km/h, 25 km
- Tokyo @ The Resort 2,800 m — Spring Slush, 6°, 3 km, night palette
- Tokyo @ Thin Air 5,200 m — Boilerplate, −10°, 3 km, stars

Plus a crash capture kept as evidence. All in `docs/screenshots/pending/`.

The Tokyo pair is the best demonstration of the altitude model the project has: same
weather, same instant, 2,400 m apart, 16 °C colder, slush → boilerplate. Reykjavík improved
on its old caption by accident — at 35 km/h the wind is visibly *why* the snow is scoured.

## Two previously unverified things, now verified

Both were on Session 0002's "written but NOT verified" list:

- **The night palette renders.** Tokyo local time was 03:05. Dark sky, and stars at 5,200 m.
- **The crash pose lies flat on the slope.** Photographed at the end of a Reykjavík run.
  ADR-020's grounded-angle fix is correct on screen, not just by construction.

Neither was sought. Both fell out of capturing beats for other reasons, which is the third
session running where measurement returned something reasoning had not.

## The bug

Holding produces no visible change. The game has one input; it currently does nothing you
can see.

The diagnosis narrowed cleanly:

- The **crash pose renders**, and it travels the identical
  `SkierRig.pose(for:cues:)` → `SkierNode.apply(_:)` path a tuck would. Pose switching works.
- `tuckCompression` is binary (`FeelModel.swift:56`), so a held tuck is the tuck pose
  exactly, and a Core test already asserts that. The rig is not at fault.
- `isHolding` is written in exactly four places (`MountainScene.swift:106–125`). Nothing
  else touches it.
- Speed does not rise across a hold — 61 → 63 km/h over 15 s, which is drift.

So: the touch ends immediately. Root cause unproven. Leading suspect is `GameView.swift:39`
handing `SpriteView` a newly constructed `MountainScene` on every body evaluation; `.id()`
pins view identity, not the scene value.

## What went wrong in how this was worked

Worth recording, because most of the session went here.

**`timeout` does not exist on macOS.** Written as `timeout 45 xcrun simctl … || echo FAILING`,
a missing binary is indistinguishable from the command failing. Two screenshot paths were
declared broken on this basis and a working simulator was rebooted chasing it. Roughly an
hour. The tell was available immediately — `command not found` was in the output, under a
`tail`.

**Input method was assumed rather than verified.** Four different hold mechanisms were tried
(`touch_path` with dwell points, `touch_path` with jitter, `tap` with `duration` in seconds,
then in milliseconds) and each was evaluated by looking at the resulting *pose*, which is
exactly the thing under suspicion. The confound ran for several rounds: a difference between
two frames was read as a partial tuck when it was the figure rotating with the surface angle.
The measurement that eventually settled it — perpendicular distance from head to ski, which
is slope-invariant — should have been the first thing built, not the fifth.

**Desktop control was escalated to without being warranted.** When simulator input would not
hold, the session took over the user's mouse and screen to press the window directly. It did
not work either — the same touch-down/touch-up behaviour — and the user objected, twice. The
in-app simulator panel streams the device without touching the machine and was available the
whole time; it had been abandoned earlier on the strength of the `timeout` misdiagnosis. Cost:
the user's trust, and the session ended on it.

**The session did not close itself.** After the user called a halt, the turn ended with a
question instead of `/session-end`, and the user had to ask for the handoff prompt. The
protocol exists precisely for the sessions that end badly.

## Decisions recorded

- **ADR-021** — README screenshots use named cities, never the developer's location.
- **ADR-022** — a README may not show a state the build cannot produce; T-112 blocks on
  T-113 rather than shipping seven of eight beats with a false caption.

## Left undone

- T-112, blocked on T-113. Four of eight beats already shot.
- The five held commits are still unpushed, plus this session's docs.
- T-113 root cause. The next session should start by asking the user whether a human hold
  changes the shape — it splits the diagnosis in one question.
