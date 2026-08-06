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

### ADR-023 — A held input is verified by concurrent capture, never by sequential capture
**Decision.** Any check of held-input behaviour on the simulator must (a) confirm the app
is actually ticking first, and (b) fire the screenshot *concurrently* with the hold, not
after it. The working recipe is `touch_path` with repeated identical points spaced by
`dt_ms`, issued in the same batch as a backgrounded `xcrun simctl io booted screenshot`
that sleeps into the middle of the hold.
**Why.** Session 0003 concluded that a held input never sustains the tuck. It does. Two
methodological faults produced that conclusion, and both are invisible from the transcript.
First, a hold call returns *after* touch-up, so a screenshot taken on the next line always
photographs the released, upright pose — the pose can only ever look unchanged. Second, the
app under test was a stale process from a previous session, frozen at 894 m / 0 km/h; a
frozen SpriteKit app photographs exactly like a live one that ignores input, and it is also
what produced the "speed only drifted 61 → 63 km/h over a 15 s press" reading.
**Consequence.** `touch_path` *does* sustain a touch — the Session 0003 environment note
saying otherwise is wrong and is corrected. Against a freshly launched app, one hold took
the skier from 43 to 71 to 80 km/h with the tuck pose rendered throughout and the EDGE
meter climbing. T-113 is closed as not-a-defect; no code was changed because none was
broken.
**Rejected.** Adding a debug launch argument to force `isHolding`. It would have made the
tuck photographable while leaving the real fault — the measurement method — in place, and
it puts a physics-affecting switch in the shipping binary to serve a screenshot.

### ADR-024 — The rig blends in angle space; poses are outputs, never inputs to a blend
**Decision.** `RigAngles` — the joint angles — is the canonical pose representation. All
interpolation happens on angles, and `SkierPose` (joint positions) is produced by solving the
bone chain once, at the end. `SkierPose.blended(toward:amount:)` and `RigPoint.blended` are
deleted rather than deprecated. Angle interpolation takes the **shortest arc**.
**Why.** Blending joint positions moves each joint along a straight chord, and a chord is
shorter than the arc the joint actually travels, so every bone contracts at intermediate `t`
and springs back at both ends. The old test suite could not see this: it asserted rigidity
only on the four *authored* poses, which are rigid under any blending scheme. Solving from
angles makes bone lengths constants of the solver — rigid at every `t` by construction rather
than by tolerance. The type-level half matters as much as the maths: a pose that carries no
blend method cannot be blended wrongly by the next caller.
**Why shortest arc.** The pole sits at −2.406 rad upright and +2.898 tucked. Both trail behind
the skier; numerically they are 5.3 rad apart, so a plain lerp sweeps the pole *forward through
the skier's chest* and back. The −0.98 rad short arc swings it the way a pole swings. Position
blending concealed this by shortening the pole instead of rotating it the long way.
**Consequence.** The joint-flip hazard that originally argued for position blending is real in
general and absent here — it needs a bone whose authored angles are ≥ π apart. The widest in
this rig is the pole between `carveRight` and `flipTuck` at 1.49 rad, leaving 1.65 rad of
headroom. `RigAnglesTests` asserts that margin so a future pose cannot quietly spend it.
Rigidity is now checked across all 56 ordered pose pairs at 51 samples each, and across every
frame of six real headless descents.

### ADR-025 — Transition state lives in the feel layer, in a value the caller carries
**Decision.** `SkierAnimator` is an immutable struct of `0...1` weights that the scene carries
between frames and advances with `advanced(for:cues:landingImpact:delta:)`. It reads
`SkierState` and `FeelCues` and writes to neither. The frame's pose is composed by blending
weights, not by selecting a state from a machine.
**Why here.** Movement is the travel between poses, and travel needs memory of how far along
it is. `SkierSimulation` cannot hold it: a landing leaves no trace in `SkierState` once
`isGrounded` flips back, and a decay timer in the simulation would put presentation inside the
thing a server re-simulates to verify a score. The feel layer is where presentation memory
belongs (ADR-010, and the same rule `FeelModel` already follows). `delta` enters here and
never reaches the simulation, so replay is untouched — `runsAreDeterministic` asserts a run is
reproducible frame-for-frame from its seed.
**Why weights, not a state machine.** Composing weights lets two transitions overlap — landing
while still holding a tuck, crashing mid-flip — without enumerating the pairs. A machine would
need an explicit edge for each, and the combinations are exactly where the old rig snapped.
**Consequence.** The carve rhythm is driven by `distanceM` rather than by a clock, so it needs
no memory at all, speeds up with the skier for free, and is identical on replay at any frame
rate. Transition rates were set against measured per-frame joint travel, not by feel alone: at
`tuckIn = 17` the head crossed 5.2 points in one frame at a 30-point body, which reads as a cut
rather than a fold. At 12 it is 4.0, with every joint holding 3.2–6.4× headroom below what a
single-frame switch would move it.

### ADR-023 amendment (session 0005) — the 894 m reading has a simpler cause
ADR-023 attributed one of Session 0003's two faults to "a stale process, frozen at 894 m /
0 km/h". Session 0005 reproduced a dead stop at **exactly 894 m**, and again at 913 m, on a
freshly launched, demonstrably live app. The terrain is deterministic, so a run that always
loses its last speed at the same place is the *simulation* stalling, not a process freezing.
**What this changes.** ADR-023's conclusion stands and was re-confirmed directly this session:
the tuck renders under a sustained hold, now including a mid-transition capture. Concurrent
capture is still the only valid way to measure held input. But the diagnostic advice needs a
third branch: two identical captures a few seconds apart mean the app is stale **or** the run
has stalled — check the speed readout and the EDGE meter before concluding either. A stalled
run reads 0 km/h with an almost empty EDGE meter and a fully opaque upright skier; a crash
reads 0 km/h with a full meter, 75% alpha and the collapsed pose.
**Consequence.** The stall is now T-116. It is a soft-lock: no crash, no summary, no input
that can restore momentum.

### ADR-026 — A run ends when the skier stops, and the ending is derived rather than stored
**Decision.** `RunOutcome.hasSettled(state, collapse:)` is a pure predicate:
`hasCrashed && velocityX == 0 && collapse >= 0.9`. No run-end flag is stored, no score is
snapshotted, and no timer is started. The only new stored state anywhere is
`MountainScene.endReason`, which exists solely to name *which* crash it was.
**Why nothing is snapshotted.** A stopped crash is an exact fixed point of the simulation:
`coast` clamps with `max(0, v - 9Δ)` and advances distance by `velocityX · Δ`, so once
`velocityX` reaches zero every field is a constant expression of itself. `step(settled, any
input, any delta) == settled`, verified across both inputs and 1/120, 1/60 and 1/30. So a
`RunScore` read on any frame the card is visible is provably identical to one read on the first
— which makes the whole class of capture bugs unreachable rather than merely guarded: no latch
to go stale, no distance ticking up under a motionless skier, no score surviving a restart.
`aSettledRunCannotDrift` is what holds this, and is the test that would catch a future `coast`
easing asymptotically instead of clamping, which would silently make the summary never appear.
**Why the beat is two existing clocks and not a new one.** The pause between the crash and the
card is `velocityX == 0` AND `crash >= 0.9`. Both already exist and are already cleared by
`restart()`; a third clock would need its own reset entry, its own frame-rate story and its own
determinism test. The pause is 0.23–1.18 s, median 0.60 s, and it scales with the severity of
the crash for free — a fast crash earns a long slide, a slow one resolves quickly.
**Why the collapse term as well as the stop.** A crash entered at walking pace stops in a couple
of frames, and gating on the stop alone would drop the card over a skier still standing upright.
`collapseFloor` is deliberately coupled to `SkierAnimator.Rate.crash`: the beat exists so the
fold can be *seen*, so retuning the fold has to move the beat with it. `Rate` is private, so
`theCollapseFloorMatchesTheAnimatorsCrashRate` pins the relationship rather than a comment
claiming it.
**Consequence for input.** A crash usually arrives with the finger still down holding the tuck,
so the next touch is often reflex. Restart now requires a *settled* run, which makes the slide a
natural debounce — the result cannot be dismissed before it appears — while leaving "restart is
one tap" literally true anywhere on screen, including on the card, which never hit-tests.
**Rejected: freezing the score at the crash frame.** It looks more correct and is not. The
crash frame itself moves 9–31 m across 30/60/120 Hz, because different deltas cross the
instability threshold in different places — roughly seventy times the 2–5 m of the slide it
would be removing. Whether the replay tape is fixed-step or carries deltas is T-403's question;
pretending the slide is the source of frame-rate dependence would write a false premise here.

### ADR-027 — A stall ends a run because it is a fixed point, not because it looks stuck
**Decision.** `RunOutcome.hasSettled` gains a second disjunct, `hasStalled(state, terrain:)`:
`!hasCrashed && isGrounded && velocityX == 0 && terrain.contactAngle(at: distanceM) >= 0`.
The run ends immediately, with `Reason.ranOutOfSpeed` ("RAN OUT OF SPEED"). `RunScore` is
unchanged — `endedInCrash` reads `hasCrashed`, which is already `false` for a stall.

**Why the counter-slope clause, and not a timer.** The obvious implementation is "stopped for
N seconds". That stores an instant, which is exactly what ADR-026 bought us out of, and it
needs its own reset in `restart()`, its own frame-rate story and its own determinism test.
The clause used instead is not a heuristic — it is the exact condition for the state to be its
own successor. `stepGrounded` accelerates by `-gravity · sin(contactAngle)` and drag vanishes
at zero speed, so a stopped skier is driven by that one term: a non-negative contact angle
gives a non-positive acceleration, `max(0, …)` clamps it back, the distance does not change,
and the angle is therefore identical next frame. Instability cannot rescue it either — the
build term scales with speed, so a held tuck at a standstill never crashes out. The same
argument that made a settled crash unsnapshottable makes a stall answerable on a single frame.

**Measured rather than asserted.** Over 120 seeds × 6 surfaces × 2 input tapes: 206 stalls,
1.17 M frames after the first one, and the predicate never went false once true. 183 of them
driven a further 20 s of alternating input at 1/20 — the coarsest delta the loop can deliver —
moved the skier 0.0 m. Across 3,600 runs the contact angle at a stall was *always* strictly
positive, minimum +0.0093: a skier stops while climbing, never on a descent.

**Why terrain in the signature.** The predicate has to ask the same question the physics
integrates, and that question is `contactAngle`. Passing the generator rather than a cached
gradient keeps everything derived; it is a value type, pure in `(seed, snowState)`, so a
server re-simulating a run to verify it already has one. Both `||` and `hasStalled`'s leading
clauses short-circuit, so terrain is sampled only on a frame where the skier is already
stopped and uncrashed — a live run pays nothing.

**Why no legibility beat.** A crash waits for `collapseFloor` so the fold can be seen. A stall
has no fold — `animator.crash` stays 0 and the skier remains upright — and the readable event
*is* the world stopping. Inventing a beat would mean storing an instant to have something to
wait on.

**Consequence for input, and the second half of the defect.** `touchesBegan` gated restart on
`hasCrashed`. Ending a stall without changing that would have produced a *worse* bug than the
soft-lock: a summary card no tap could dismiss, while the same tap started a tuck underneath
it. The gate is now `isRunOver`. The crash debounce survives as a separate clause; a stall
needs no equivalent, since it can only be reached with the skier already at a standstill.

**Consequence for feel.** `Reason.isCrash` is `false` for a stall, so `feedback.crash()` no
longer fires on every run ending — a haptic thump there would report an impact that never
happened.

**What this does not fix.** A stall is now a *legible* ending, not a rare one: 8.7% of runs in
the sweep, and the earliest found is 17 m from the drop-in. That is a terrain and drop-in-speed
question — the ridge octave locally exceeds the base gradient, and 8 m/s buys only 3.3 m of
climb — and it is now T-119, not a silent soft-lock.
