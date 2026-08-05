# Whiteout

An iOS endless alpine racer whose snowpack physics are generated from the player's real
local weather. Swift 6 / SpriteKit / SwiftUI, with a Vercel backend from M3 onward.

**This file is loaded into every session. Keep it under ~200 lines and change it rarely.**
Anything that changes session to session belongs in `docs/`, not here.

---

## Start every session here

1. Run `/session-start`. It reads state, verifies the build, and reports what is ready.
2. If the slash command is unavailable, read in this order:
   `docs/STATE.md` → `docs/ROADMAP.md` → `docs/DECISIONS.md`.

Do not begin work before reading `STATE.md`. It is the only file that knows what happened
last session.

## End every session here

Run `/session-end`. It will not let you finish with a red test suite, and it produces the
recap and handoff prompt.

---

## Invariants

These are load-bearing. Breaking one silently is the most expensive thing a session can do.
If you believe one must change, that is an ADR in `docs/DECISIONS.md`, not an edit.

1. **`WhiteoutCore` imports no UI framework.** No UIKit, SwiftUI, or SpriteKit. It is the
   pure, headless simulation, testable in milliseconds without a simulator. Rendering types
   belong in `App/`.

2. **The simulation is deterministic.** A run is fully reproducible from `(seed, input
   tape)`. No `Date()`, no `Math.random`, no ambient state inside `SkierSimulation`,
   `TerrainGenerator`, or `SeededRandom`. This is what makes ghosts 2 KB and lets the
   server verify a leaderboard score by re-simulating it. Losing it forfeits anti-cheat.

3. **Feel never writes to physics.** `FeelModel` reads simulation state to produce camera,
   shake, and audio cues. It must never influence the simulation, or verification breaks.

4. **No purchase may alter physics, scoring, or run duration.** Storms and cosmetics are
   sideways content. Altitude changes speed, so altitude is unlocked by distance and is
   never sold. See ADR-008.

5. **Weather must be load-bearing, not cosmetic.** Any weather feature has to change what
   the correct *decision* is, not just what the screen looks like. A filter is a failure.

6. **Gameplay never blocks on the network.** Conditions resolve before a run starts and are
   then immutable. Location denied, API down, airplane mode — all fall back to playable
   conditions, never an error screen.

7. **Every session ends green.** `swift test` and the iOS build both pass, and the work is
   committed. A red suite is never handed off.

---

## Commands

```bash
cd Core && swift test          # 85+ tests, runs in ~30ms, no simulator needed
xcodegen generate              # regenerate Whiteout.xcodeproj after adding files
./scripts/verify.sh            # full gate: tests + iOS build
```

`Whiteout.xcodeproj` is **generated** from `project.yml` and is gitignored. Never edit it
by hand. Adding a new source file requires re-running `xcodegen generate`.

Simulator builds need `CODE_SIGNING_ALLOWED=NO` (no team is configured).

---

## Layout

```
Core/          WhiteoutCore — pure simulation. Weather, snow model, physics, terrain, palette.
App/Sources/   iOS app. Scene rendering, SwiftUI shell, haptics, audio.
docs/          Project truth. State, roadmap, decisions, design.
scripts/       verify.sh and tooling.
```

## Conventions

- Swift 6 language mode, strict concurrency. `let` by default; structs over classes.
- Immutability is not optional in `Core` — derive new values, never mutate.
- Files stay under ~400 lines. Split by feature, not by type.
- Swift Testing (`import Testing`, `@Test`, `#expect`). Not XCTest.
- Comments explain *why*, never *what*. Prefer none over restating the code.
- Real-time audio render blocks must be `nonisolated` — see ADR-011, it crashes otherwise.

## Working style

Autonomy is high. Make ordinary engineering calls, record the notable ones as ADRs, and
stop only for genuinely irreversible or ambiguous choices. Use subagents and parallel work
freely; a session should accomplish a lot.

Report honestly. If something is untested, say so — haptics cannot be verified in the
simulator, and claiming otherwise poisons every later session that trusts the log.
