# Architecture

## The shape, and why

```
┌─ Core/  WhiteoutCore ──────────────────────────────────┐
│  No UI framework. Pure, deterministic, ~30ms to test.  │
│                                                        │
│  StationObservation  ← real weather, provider-neutral  │
│         ↓ AltitudeTranslation                          │
│  MountainWeather     ← lifted to a peak's elevation    │
│         ↓ SnowState.classify                           │
│  SnowState           ← the snowpack, 6 states          │
│         ↓                                              │
│  SnowPhysics · ScenePalette · TerrainGenerator         │
│         ↓                                              │
│  SkierSimulation     ← pure step function              │
│         ↓                                              │
│  FeelModel           ← reads state, never writes       │
└────────────────────────────────────────────────────────┘
                          ↓
┌─ App/ ─────────────────────────────────────────────────┐
│  MountainScene (SpriteKit) · GameView (SwiftUI)        │
│  RunFeedback (haptics + procedural audio)              │
│  ConditionsStore · RunTelemetry                        │
└────────────────────────────────────────────────────────┘
```

**Everything flows one way.** Weather determines the snowpack; the snowpack determines
physics, palette, and terrain roughness; those determine the run. Nothing flows back.

## Why Core is UI-free

Three payoffs, all of which are lost the moment a `import UIKit` appears:

1. **The suite runs in ~30 ms with no simulator.** Fast enough that no session has an
   excuse to skip it, which is what makes it a viable gate.
2. **The server can run the same code.** Score verification (T-403) re-simulates a
   submitted run from `(seed, input tape)`. That requires a simulation with no device
   dependencies.
3. **Feel cannot corrupt physics.** `FeelModel` produces camera, shake, and audio cues by
   reading state. If it could write, the simulation would stop being verifiable.

## Determinism

A run is a pure function of `(seed, input tape)`. The seed derives from
`geohash | hour | peak | snowState | roundedTemperature`, which means two players in the
same town in the same hour ski the *same mountain* and can compare honestly, while the next
hour brings new terrain.

`SeededRandom` is *indexed*, not sequential: `raw(at: index)` is a pure function with no
cursor. Terrain metre 250,000 can be evaluated without generating the 249,999 before it —
which is what makes replays, ghosts, and constant memory possible.

## Latency

The rule: **no third-party service is ever awaited during gameplay.**

```
boot      → GET conditions (geohash-4 bucket) → ConditionPacket, <1KB
gameplay  → 0 network calls; runs fully offline from the seed
post-run  → score submission, async, never blocks restart
```

Geohash precision 4 is ~20 km cells. High cache hit rate in any populated area, and the
device's precise coordinates never leave it. The privacy win and the latency win are the
same decision.

Conditions are stale-while-revalidate on a 15-minute TTL — weather moves on ten-minute
scales, so serving a 12-minute-old packet instantly beats a fresh one in 800 ms.

## Failure posture

Every dependency has a playable fallback. Location denied, network down, provider erroring,
airplane mode — all resolve to `RunConditions.fallback()`, a cold clear morning that best
teaches the controls. A weather game that refuses to start without weather has confused its
input for its product.

## Build

`Whiteout.xcodeproj` is **generated** from `project.yml` by xcodegen and is gitignored.
Adding a source file requires `xcodegen generate` before it is visible to the build —
`scripts/verify.sh` does this automatically.

## Backend (M3+, not yet built)

Next.js on Vercel Fluid Compute · Neon Postgres for durable state · Upstash Redis for the
conditions cache and leaderboard sorted sets · Vercel Blob for ghost input tapes · Vercel
Cron to pre-warm populated geohash buckets.
