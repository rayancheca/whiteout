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

### ADR-017 — A generated `UILaunchScreen` is what makes the app fullscreen
**Decision.** `INFOPLIST_KEY_UILaunchScreen_Generation: YES` in `project.yml`. The canvas
ignores the safe area; the overlays inherit it.
**Why.** Without a launch-screen entry iOS runs the app in legacy compatibility mode and
letterboxes it. Measured on iPhone 17 Pro: **564 × 376 pt inside an 874 × 402 pt display**,
so 36% of the width was black bars and the game was rendering into two thirds of the screen
it had. Nothing in the code is wrong when this happens, which is exactly why it survived a
whole milestone — the bug lives in the *absence* of a plist key, so there is no line to read.
**Consequence.** Scene width grew 55%, which moves `baselineY`, the horizon, and how much
terrain is on screen. Skier scale for T-101 had to be chosen against the corrected frame,
which is why this was done first.
**Rejected.** Reading insets from a `GeometryReader` that has `ignoresSafeArea` applied
above it — that zeroes `safeAreaInsets`, and the first attempt put the conditions card under
the Dynamic Island. The reader must *keep* its safe area and the canvas alone opts out,
reconstructing the full display size as `size + insets`.

### ADR-018 — The skier rig is a pure pose solver in `WhiteoutCore`
**Decision.** `SkierRig` lives in Core: a normalised skeleton (1.0 = standing height, origin
at the ski/snow contact point) and a pure `pose(for:cues:)`. `SkierNode` in `App/` renders it
with SpriteKit. Colours are generated in `ScenePalette`, not chosen in the renderer.
**Why.** It follows `FeelModel`'s precedent — presentation logic that reads simulation state
and never writes to it (ADR-010). The payoff is that proportion, silhouette and legibility
become unit-testable in ~30 ms with no simulator, which is how the colour defect below was
found at all. It also keeps the pose reusable by a future server-side replay renderer.
**Rejected.** Building the rig in the SpriteKit layer, which would have made every one of
these properties verifiable only by screenshot.

### ADR-019 — The skier is drawn against the near ridge, not the sky
**Decision.** The legibility guarantee is asserted against `ridge(depth: 0.42)` and the snow,
and the skier is drawn in two tones pinned near opposite ends of the lightness axis with a
spread of ≥ 0.60. `ScenePalette` owns the ridge-band colours so the test can compute them.
**Why.** Measured from the scene's own layout: the skier occupies 0.34–0.42 of screen height
while the nearest parallax band fills everything below 0.55. Reaching the sky would need
~111 m of relative altitude, which no jump produces. So the backdrop is that band, whose
lightness runs 0.25–0.59 — the *middle* of the axis. Anything anchored to `rockNear` sits
inside that range: the old fill separated from it by **0.02** at night, about one 8-bit code
value. One tone cannot solve this, because the one place you cannot be is the middle. Two
tones far apart always leave one of them far from any backdrop.
**Rejected.** A single adaptive tone (unsatisfiable, per above). Also rejected: testing
contrast against `skyHorizon`/`skyZenith` — the first version of this work did exactly that,
passed, and was measuring a backdrop the skier is never seen against.

### ADR-020 — The drawn ski bridges terrain over the length it is drawn
**Decision.** When grounded, `zRotation` comes from
`terrain.surfaceAngle(at:halfLengthM:)` over the *rendered* ski length, not from
`skier.rotation`.
**Why.** The drawn skier is about nine times life size, so its 34.5 pt ski spans ~17 m of
terrain while physics computes contact over 1.7 m. Drawn at the physical angle the ski
visibly refuses to lie on the slope — tip buried, tail in the air. This is the rendering
analogue of ADR-012: a plank spans the surface it covers, and the drawn plank is longer.
**Consequence.** Presentation-only and read-only, so the `(seed, input tape)` a server
re-simulates is untouched. The placeholder capsule hid this because it had no long
horizontal element to reveal it.

### ADR-021 — README screenshots use named cities, never the developer's location
**Decision.** The screenshots that demonstrate the altitude model resolve their weather
from a named showcase city (Tokyo), not from `Origin.here`. No capture published to the
repository may be taken with the real device location.
**Why.** The repository is public (ADR-016), and the conditions card prints the resolved
place, temperature, wind and visibility. Captured from `.here`, that quartet is a location
disclosure — geohash bucketing protects the *request*, not a screenshot of the answer. A
named city is also reproducible by anyone cloning the repo, which the developer's back
garden is not, and it keeps "real live Open-Meteo data" literally true.
**Consequence.** The caption for those beats names the city instead of saying "your real
local weather". The claim gets weaker; it also becomes checkable.
**Rejected.** Real location (discloses region). The simulator's default coordinate
(Cupertino — neutral, but it makes the weather story arbitrary while *looking* personal,
which is the worst of both).

### ADR-022 — A README may not show a state the build cannot produce
**Decision.** T-112 is blocked on T-113 rather than shipping seven of eight beats. No
screenshot or caption describing the tuck goes into the README until a held input actually
renders the tuck.
**Why.** The push was held in the first place because the existing captures misrepresented
the app — a black capsule and a letterboxed frame. Publishing a "tucked, flat out" caption
while holding produces no visible change would be the identical failure with fresh pixels
on it, and would additionally retire the question: a reader who sees the tuck documented
has no reason to report that it does not happen.
**Consequence.** Four verified captures sit unused in `docs/screenshots/pending/` until
T-113 lands. That is the cost, and it is smaller than publishing a false claim.
