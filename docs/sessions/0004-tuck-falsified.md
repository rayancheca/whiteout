# Session 0004 — T-113 falsified, README beats live, mute button

> **Reconstructed in session 0005** from `docs/STATE.md` as it stood at commit `5c71092`,
> the three session-0004 commits, and ADR-022/023. Session 0004 updated `STATE.md` and
> `DECISIONS.md` but never wrote its log, so this fills the gap rather than leaving the
> archaeology layer permanently missing an entry. It is second-hand; the primary sources are
> the commits themselves.

## Commits

- `f44de0f` fix: T-113 was never a defect — the tuck renders; refresh all 8 README beats
- `a38d06c` feat: mute button for the synthesised weather audio (T-115)
- `5c71092` docs: session 0004 — T-113 falsified, all 8 README beats live, mute button

## What happened

**T-113 was closed as not-a-defect.** Session 0003 had reported that a held input never
sustains a tuck. It does. No code was changed, because nothing was broken — the *measurement*
was wrong, in two independent ways, neither visible from a transcript:

1. A hold call returns *after* touch-up, so a screenshot taken on the next line always
   photographs the released, upright pose. The pose could only ever look unchanged.
2. The app under test was a stale process, frozen at 894 m / 0 km/h from a previous session.
   A frozen SpriteKit app photographs exactly like a live one ignoring input.

Against a freshly launched app, one sustained `touch_path` took the skier 43 → 71 → 80 km/h
with the tuck rendered throughout and the EDGE meter climbing. Recorded as **ADR-023**.

The user confirmed by hand at the start of the session that holding does tuck the skier on the
simulator. That single answer split the cause in one step.

**T-112 done.** All eight README beats recaptured fullscreen at 2622 × 1206 against live
Open-Meteo data with the real skier rig, verified free of the dev panel by a pixel check.
Beats 3 and 4 were reshot because the pending versions had the dev panel open, one showing a
*locked* peak directly beneath a caption about peaks unlocking by distance — the situation
ADR-022 exists to prevent. Beats 5 and 6 were the first captures of carving and tucking with
the real rig.

**T-115 added and done.** A mute button for the synthesised wind and edge noise, requested
mid-session. It lives in a shared `AudioSettings` rather than on the scene: `GameView` builds
a fresh `MountainScene` every body evaluation while `SpriteView` keeps presenting the old one
until `sceneID` changes, so a flag passed at construction lands on a scene nobody sees. Muting
zeroes the gains rather than stopping the engine, so there is no restart click.

## What was learned

- `touch_path` **does** sustain a touch. The session-0003 environment note saying otherwise
  was wrong and was corrected.
- Held-input behaviour must be verified by *concurrent* capture, never sequential (ADR-023).
- Confirm the app is actually ticking before measuring anything.
- The `GameView` scene-rebuild discovery became **T-114**, still open.

## Correction recorded later

Session 0005 reproduced a dead stop at **exactly 894 m** on a freshly launched, demonstrably
live app, and again at 913 m. Since the terrain is deterministic, that reading is better
explained by the simulation **stalling** than by a frozen process. ADR-023's conclusion stands
— the tuck renders, and concurrent capture is still mandatory — but its second diagnosed cause
was over-attributed. See the ADR-023 amendment and **T-116**.
