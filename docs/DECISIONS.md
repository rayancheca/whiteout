# Decision Log

Append-only. Never edit or delete an entry — supersede it with a new one that references it.

Each entry records what was **rejected** and why. That is the part that stops a future
session re-opening a settled question, and it is the part a summary would drop first.

Format: `ADR-NNN — Title` · Decision · Why · Rejected.

---

### ADR-001 — Build the weather-synced alpine racer
**Decision.** Of five candidate concepts, build the endless alpine racer driven by real
local weather.
**Why.** It was the only candidate where every third-party dependency resolves *before* a
run starts and can be cached, keeping the network entirely off the frame-time critical
path. Proven genre, no regulatory surface, inherently screenshot-viral.
**Rejected.** *Kinetic AR Brawler* — Spotify deprecated the `audio-features` BPM endpoints
for new apps in Nov 2024, so the core mechanic's API no longer exists. *AI Dungeon Forge* —
per-user generative cost (~$0.04–0.20/session) exceeds hybrid-casual ARPDAU; unit economics
are inverted, plus permanent NSFW moderation liability. *Geo Market Tycoon* — gambling-
adjacent, market-data licensing, and needs player density that does not exist at launch.
*Real-Life RPG* — GitHub-as-XP caps the audience at developers; four OAuth consents before
first play destroys the funnel.

### ADR-002 — Swift + SpriteKit, iOS-first
**Decision.** Native Swift 6 with SpriteKit and a SwiftUI shell.
**Why.** Best achievable game feel — 120 Hz ProMotion, Metal, Liquid Glass. Xcode and the
iOS Simulator are on the build machine, so builds are verifiable end to end.
**Rejected.** *TypeScript + PixiJS + Capacitor* — would have added an instant-play web build
as a viral surface, but caps feel and fidelity. *Unity 6* — not installed, GUI-driven, and
not autonomously verifiable, trading away the fast feedback loop for engine features a 2.5D
racer does not need. *React Native + Skia* — real risk of missing locked 60 fps under
particle load, which is fatal for a game that lives on feel.
**Consequence.** Android is a full rewrite. Accepted.

### ADR-003 — Open-Meteo, not OpenWeather
**Decision.** Open-Meteo is the weather provider; the response is mapped into a
provider-neutral `StationObservation`.
**Why.** It reports `freezing_level_height`, `snowfall`, `snow_depth` and `visibility` on
the free tier. OpenWeather reports none of the snowpack fields, so it literally cannot drive
the snow-state model — the original concept's provider choice would have forced weather back
into being a cosmetic filter. Also needs no API key, removing a secret from the binary.

### ADR-004 — No real topography in 1.0
**Decision.** Terrain is procedurally generated from a seed, not from Mapbox elevation data.
**Why.** Real topography adds cost, latency, and a tile-licensing dependency for an
authenticity gain players cannot feel at 80 km/h. Parked, not discarded.

### ADR-005 — Altitude Translation
**Decision.** Lift the player's real local weather to alpine elevation using the
environmental lapse rate, a temperature-dependent snow-to-liquid ratio, and a bounded
power-law wind profile.
**Why.** Rendering local weather directly gives a player in Lagos or Miami nothing — a fatal
reach problem hidden inside a clever idea. Translation gives every player on Earth a real,
personal, materially different mountain day.

### ADR-006 — Snow-state classification is ordered most-destructive-first
**Decision.** `SnowState.classify` tests freeze–thaw before fresh snow.
**Why.** A snowpack rained on and refrozen is crust *no matter how much powder fell on top*.
Checking fresh snow first reports a powder day on conditions every skier would recognise as
survival crust. The ordering is the model, not an implementation detail.

### ADR-007 — No season pass. Storm Archive instead.
**Decision.** Monetize through a permanent, growing catalog of raceable historic weather
events, plus cosmetics and opt-in rewarded video. No battle pass, no soft currency.
**Why.** A season pass creates FOMO, a live-ops content calendar that must be fed forever,
and a content cliff when a cadence is missed. The Archive never expires, costs almost
nothing per item to author (a weather record plus a curated seed), and only this game can
sell it. The one-time "Full Archive" SKU captures whale LTV without a subscription.
**Rejected.** Season pass, soft/gem currency (it is how pay-to-win drift sneaks in),
premium paid download (caps reach and forfeits the organic loop).

### ADR-008 — No purchase may alter physics, scoring, or run duration
**Decision.** A hard architectural invariant, verified by an automated check (T-508).
**Why.** Storms are *sideways* content — each carries its own isolated leaderboard, so
buying one grants a new place to compete, never an advantage where you already compete.
Stated as an enforceable rule rather than a promise.

### ADR-009 — Altitude is progression, and is never sold
**Decision.** Peaks (2,800 m → 5,200 m) unlock by cumulative distance skied.
**Why.** Two measurements forced it. At a fixed 2,800 m a tropical player gets slush every
day, and through the northern summer *every* player gets packed or slush — four of six snow
states became unreachable for half the year. Raising the mountain restores the full range
from the same real weather. Thinner air also genuinely reduces drag, so altitude changes
speed — which is exactly why it cannot be a purchase (ADR-008).

### ADR-010 — The simulation is pure, headless, and deterministic
**Decision.** `WhiteoutCore` imports no UI framework. A run is reproducible from
`(seed, input tape)`.
**Why.** It makes ghosts 2 KB, lets the server verify a leaderboard score by re-simulation
instead of trusting the client, and keeps the whole model testable in ~30 ms with no
simulator. Anti-cheat is a consequence of the architecture rather than a bolted-on layer.
**Consequence.** `FeelModel` may read simulation state but must never write to it.

### ADR-011 — Real-time audio render blocks must be `nonisolated`
**Decision.** `RunFeedback.makeNoiseNode` is explicitly `nonisolated`.
**Why.** As a static member of a `@MainActor` type it silently inherited main-actor
isolation; the render block then called `swift_task_checkIsolatedSwift` on the real-time
audio thread and hard-crashed with SIGTRAP the moment audio started. The isolation is
invisible at the call site and the crash lands in libdispatch, so it reads as an
AVFoundation fault rather than a concurrency one. A comment stating the constraint did not
prevent it — only the keyword does.

### ADR-012 — Skis bridge surface texture
**Decision.** `TerrainGenerator.contactAngle` samples over a 1.7 m ski length, separate from
the finer `slopeAngle`.
**Why.** The fine terrain octave has a sub-metre wavelength, so a ±0.5 m window read every
sastruga as a ~0.5 rad cliff and the skier launched off flat ground. A ski is a rigid plank
that spans texture rather than following it. This is physics, not smoothing.

### ADR-013 — Carving always costs speed, scaled by grip
**Decision.** `speedRetention` applies a `demand × grip` scrub on every carve, plus a
penalty above the grip limit.
**Why.** Penalising only over-demand made any carve below the grip limit free, so on packed
snow tucking and carving were indistinguishable and the game's single decision had no
consequence — the running build hit top speed while upright. Scrub scales *with* grip
because shedding speed needs an edge that bites; an earlier form scaled with `1 - grip`,
which scrubbed hardest on ice, exactly where a ski cannot scrub at all.

### ADR-014 — Landscape orientation
**Decision.** Landscape only.
**Why.** An endless descent needs horizontal sightline to read terrain ahead; the genre is
uniformly landscape.
**Rejected.** Portrait, which suits one-thumb play and vertical video better. Revisit only
with evidence from beta.

### ADR-015 — The repository is the memory
**Decision.** Durable session state lives in versioned files under `docs/`. The handoff
prompt is a thin pointer, not a state transfer.
**Why.** A pasted prompt is copy-paste fragile, unversioned, and grows without bound — if an
old handoff was wrong you cannot diff it. Files are versioned, diffable, and read
automatically. `CLAUDE.md` stays small because it is injected into every session on every
turn; volatile state goes in files read on demand.

### ADR-016 — Public GitHub repository
**Decision.** Public repo from the start.
**Why.** Off-machine backup, full history across sessions, and CI on every push.
**Consequence.** Game design and monetization strategy are visible while building. Accepted
knowingly. No secrets, keys, or private data may ever be committed.
