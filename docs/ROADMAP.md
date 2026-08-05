# Roadmap

**Ship line: full commercial 1.0** — playable core, social loop, and monetization, on the
App Store.

Two gates are placed inside that scope so monetization is tuned against real behaviour
rather than guesses: an internal TestFlight build at the end of M1, and a public beta at
the end of M4.

Task IDs are stable and never reused. `deps` must all be `done` before a task is ready.

Status: `todo` · `doing` · `done` · `blocked` · `parked`

---

## M0 — Foundation ✅ done

The weather-to-physics engine and a playable prototype.

| ID | Task | Status |
|----|------|--------|
| T-001 | `WhiteoutCore` package, seeded determinism, terrain generation | done |
| T-002 | Altitude Translation — lift local weather to alpine elevation | done |
| T-003 | Snow State Model + `SnowPhysics` substrate | done |
| T-004 | OKLCH palette generated from weather | done |
| T-005 | Open-Meteo client, geohash privacy bucketing, solar position | done |
| T-006 | SpriteKit renderer — parallax, aerial perspective, grain | done |
| T-007 | Peaks / altitude progression | done |
| T-008 | `SkierSimulation` — tuck/carve, jumps, landings, crashes | done |
| T-009 | Feel pass — camera, shake, speed lines, trail, haptics, procedural audio | done |
| T-010 | Project infrastructure — git, docs, session protocol, hooks | done |

---

## M1 — Vertical Slice → 🚩 internal TestFlight

The game looks and feels like a product. No server, no money.

| ID | Task | Done when | Deps | Status |
|----|------|-----------|------|--------|
| T-101 | Skier character art + rig | Real silhouette replaces the capsule; readable at speed | — | done |
| T-102 | Skier animation states | Tuck, carve L/R, air, flip, land, crash all transition cleanly | T-101 | done |
| T-111 | Rig blending in angle space | Bones stay rigid *mid-blend*, not just in the authored poses | T-101 | done |
| T-113 | ~~Held input never sustains a tuck~~ — **not a defect** | Closed: the tuck renders and speed rises (43→71→80 km/h) under a sustained hold. The Session 0003 report was a measurement artefact — see ADR-023 | T-101 | done |
| T-112 | Refresh README screenshots | All 8 recaptured fullscreen with the real skier; caption 6 no longer describes the deleted squash; then push | T-101, T-110, T-113 | done |
| T-114 | `GameView` rebuilds the scene every body evaluation | `makeScene` no longer constructs a `MountainScene` (and a `TerrainGenerator`) on every SwiftUI re-render; the comment at `GameView.swift:83` stops claiming a caching behaviour that does not exist | — | todo |
| T-115 | Mute button | One tap silences the synthesised wind and edge noise; state survives relaunch and a conditions re-resolve; haptics unaffected | — | done |
| T-116 | A run can stall to a dead stop instead of ending | The skier can no longer reach 0 km/h and sit there: a run that loses all speed on a flat resolves into a crash, a summary, or a recovery. Observed at 913 m — EDGE meter near empty, no crash, fully upright, motionless indefinitely with no input able to restart momentum. **Session 0006: reproduced at 38 m on Reykjavík / Packed, within seconds of the drop-in — far cheaper to hit than the 894/913 m cases, so start there.** T-105 built the place it should resolve to: a stall ends the run by satisfying a second disjunct in `RunOutcome.hasSettled`, and `RunScore.endedInCrash` already carries the distinction | — | todo |
| T-103 | Art direction pass | Atmospheric Realism reference set agreed and applied; volumetric light, depth of field | — | todo |
| T-104 | Snow surface treatment | Powder/crust/ice visually distinct at a glance, not just in the HUD | T-103 | todo |
| T-105 | Crash + run-summary flow | Crash reads clearly, summary shows distance/air/flips/conditions, restart is one tap | T-102 | done |
| T-106 | Audio pass | Layered wind, edge, impact, ambience; mix balanced against the procedural base. **Also: the crash is currently the game's quietest moment.** `FeelModel` shake measures 0.78–0.93 on the frame before a lost edge and exactly 0 on the crash frame. That guard is correct — both shake terms model *riding*, and relaxing it makes a crashed body chatter as though still on its edges — so the fix is a separate crash channel summed in `applyShake`, not a change to the guard | — | todo |
| T-107 | Main menu + drop-in flow | Conditions card as the hero; start, settings, peak select | T-105 | todo |
| T-108 | Device performance pass | Locked 120 Hz on ProMotion, no frame drops in a whiteout | T-103 | todo |
| T-109 | **Gate: internal TestFlight** | Signed build installed and played on real hardware; haptics verified | T-101…T-108 | todo |
| T-110 | Fullscreen + safe-area pass | Edge-to-edge canvas on every device from iPhone X on; HUD and cards clear the notch and home indicator in both landscape orientations | — | done |
| T-117 | Split `MountainScene` | The file is ~760 lines against a ~400 house limit. Build/layout of sky, ridges, slope, trail, spray and snowfall are separable from the frame loop and the input handling. Not urgent, but every task that touches the scene makes it worse | — | todo |
| T-118 | A second finger releases the tuck | `touchesEnded` sets `isHolding = false` unconditionally, so lifting *any* finger drops the tuck even while another is still down. Pre-existing, found while reading the input path for T-105. Track the touch that started the hold | — | todo |

## M2 — Game Systems

Everything a player expects around the core loop.

| ID | Task | Done when | Deps |
|----|------|-----------|------|
| T-201 | Persistence layer | Lifetime distance, bests, unlocks, settings survive relaunch and migrate safely | — |
| T-202 | Run scoring + local leaderboards | Per-snow-state and per-peak personal bests | T-201 |
| T-203 | Onboarding | First run teaches one-button control without a wall of text | T-107 |
| T-204 | Settings screen | Haptics, audio, reduced motion, units. Absorbs the T-115 mute button, which currently floats as its own control | T-201 |
| T-205 | Accessibility | VoiceOver on menus, reduced-motion path, colourblind-safe HUD, contrast audit | T-204 |
| T-206 | Peaks progression UX | Unlock moments feel earned; progress toward next peak visible | T-201 |

## M3 — Backend Foundation

| ID | Task | Done when | Deps |
|----|------|-----------|------|
| T-301 | Vercel project + Next.js API skeleton | Deployed, health endpoint green | — |
| T-302 | Storage: Neon Postgres + Upstash Redis | Provisioned via Marketplace, schema migrated | T-301 |
| T-303 | Conditions endpoint | Open-Meteo moves server-side; geohash cache, stale-while-revalidate, cron warm | T-302 |
| T-304 | Device identity / anonymous auth | Stable player ID without an account; no PII | T-302 |
| T-305 | GitHub Actions CI | `swift test` + iOS build on every push; branch protection | — |
| T-306 | Client migration to server conditions | App reads `/api/conditions`; offline fallback still works | T-303 |

## M4 — Social Loop → 🚩 public beta

The retention engine. Everything in M5 depends on this existing first.

| ID | Task | Done when | Deps |
|----|------|-----------|------|
| T-401 | Leaderboard storage | Redis sorted sets, Home Mountain + Daily ladders | T-302 |
| T-402 | Daily Challenge | One real weather station worldwide, same for every player, resets at midnight | T-401 |
| T-403 | Score submission + replay verification | Server re-simulates from `(seed, input tape)`; mismatches rejected | T-401, T-304 |
| T-404 | Ghost replays | Input tapes stored in Blob; race a friend's line | T-403 |
| T-405 | Share cards | Generated image with conditions + score; the conditions are the boast | T-402 |
| T-406 | Friends / follow | Compare against a chosen set, not just global | T-401 |
| T-407 | **Gate: public TestFlight beta** | Real players, real leaderboards, telemetry flowing | T-401…T-406 |

## M5 — Monetization

Deliberately after M4: the Storm Archive is worthless without ladders to compete on, and
pricing tuned against zero players is guesswork.

| ID | Task | Done when | Deps |
|----|------|-----------|------|
| T-501 | StoreKit 2 integration | Products load, purchase, restore, entitlements persist | T-201 |
| T-502 | Storm Archive data model | Historic weather events as records; deterministic seeds; own leaderboard per storm | T-401 |
| T-503 | Storm curation pipeline | Tooling to author a storm from real historical data | T-502 |
| T-504 | Store UI | Single storms, collections, Full Archive; no soft currency anywhere | T-501, T-502 |
| T-505 | Cosmetics | Skis, jackets, trails; some earnable free | T-501 |
| T-506 | Rewarded video | Opt-in only — revive and time-of-day reroll. Zero interstitials | T-501 |
| T-507 | Receipt validation | Server-side verification; entitlement sync across devices | T-501, T-304 |
| T-508 | Monetization audit | Automated check that no SKU touches physics, scoring, or run duration (ADR-008) | T-504, T-505 |

## M6 — Live Ops & Polish

| ID | Task | Done when | Deps |
|----|------|-----------|------|
| T-601 | Analytics + crash reporting | Funnel, retention, crash-free rate visible | T-301 |
| T-602 | Remote config | Physics and economy tunable without a release | T-301 |
| T-603 | Push notifications | Daily challenge and storm-day alerts, opt-in | T-402 |
| T-604 | Localization | String catalog; launch languages chosen from beta data | T-407 |
| T-605 | Performance + battery pass | Sustained 120 Hz, thermals and battery measured on device | T-108 |
| T-606 | Security review | Anti-cheat hardened, no secrets in binary, endpoints rate-limited | T-403 |

## M7 — Launch

| ID | Task | Done when | Deps |
|----|------|-----------|------|
| T-701 | App Store assets | Screenshots, preview video, description, keywords | T-407 |
| T-702 | Privacy manifest + App Privacy | Data collection declared; location coarsening documented | T-601 |
| T-703 | Age rating + IAP review prep | All SKUs submitted and approved | T-504 |
| T-704 | Marketing site | Landing page on Vercel | T-701 |
| T-705 | **Gate: App Store submission** | Submitted for review | T-701…T-704 |

---

## Parking lot

Deliberately out of 1.0. Recorded so they stop being re-proposed.

- Android port
- Apple Watch companion
- Real topographic terrain from Mapbox elevation (cost + latency, ADR-004)
- AI post-run commentary (decorative; cut from v1 scope)
- Multiplayer real-time racing
- Seasonal events / battle pass (explicitly rejected, ADR-007)
