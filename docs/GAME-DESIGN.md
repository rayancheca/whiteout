# Game Design

## The thesis

Your real local weather generates the mountain you ski. Not as a filter — as physics. What
the correct decision *is* changes with the actual snowpack outside your window.

If a weather feature only changes what the screen looks like, it has failed. That is the
test every feature is held to.

## The core loop

One input.

- **Hold** — tuck. Drag drops to 52%, speed builds, no steering. Instability accumulates at
  a rate set by the snowpack's `chatter`.
- **Release** — carve. Speed scrubs, scaled by `grip`. Instability bleeds off.

On powder (`chatter` 0.05) you can hold almost indefinitely. On boilerplate (`chatter` 0.92)
a two-second tuck puts you down. Same button, completely different game, decided by real
weather.

Jumps are not scripted: the skier goes airborne wherever terrain falls away faster than
gravity, so kickers emerge from the seed. Holding in the air backflips. Landings are judged
against `float` — powder swallows an attitude crust rejects outright.

## The six snow states

Classification is ordered most-destructive-first (ADR-006).

| State | Feel | Produced by |
|---|---|---|
| **Powder** | Forgiving, slow, huge spray | ≥8 cm new, ≤ −2 °C, calm |
| **Packed** | The neutral baseline | Ordinary winter day |
| **Crust** | Fast, loud, unforgiving | Thaw in last 24 h, refrozen now |
| **Slush** | Grabby, punishes over-carving | Above +1.5 °C, or rain at altitude |
| **Ice** | Maximum speed, minimum grip | Deep cold, no new snow, wind scour |
| **Wind Slab** | Uneven, unpredictable launches | Fresh snow + gusts ≥45 km/h |

No state is strictly better. Powder is forgiving *and* slow; ice is lethal *and* fastest.
"Good conditions" depends on what you are chasing.

## Altitude as progression

Peaks unlock by cumulative distance: The Resort (2,800 m) → The Spine (3,600 m) → The Col
(4,400 m) → Thin Air (5,200 m).

Higher is colder, so the same real weather reaches snow states the resort cannot — this is
what keeps the model exercising its full range in July. Thinner air also reduces drag, so
high peaks are genuinely faster and less forgiving. Because altitude changes speed, it is
never purchasable (ADR-008/009).

## Competition

Weather-driven difficulty makes a single leaderboard unfair. Inverted into the hook — two
ladders:

- **Home Mountain** — your translated local conditions. Personal, daily.
- **The Daily** — one real weather station on Earth, identical for every player, rotating
  at midnight. *"Today everyone races Chamonix. 14:00 local: heavy snow, 40 km/h gusts,
  visibility 60 m."*

The Daily is the Wordle mechanic: one shared, fixed, real challenge, and everyone has the
same story. Deterministic seeding makes the share card provably honest.

## Monetization

No soft currency. Direct prices only. Nothing sold touches physics, scoring, or run
duration (ADR-008).

| Tier | Item | Price |
|---|---|---|
| Free forever | Home Mountain, unlimited, never ad-gated | — |
| Rewarded video (opt-in) | One revive; time-of-day reroll. Zero interstitials | — |
| Single storm | Any archived historic event | $1.99 |
| Collection | Themed 5-pack | $6.99 |
| **Full Archive** | Every storm plus all future storms, one-time | $19.99 |
| Cosmetics | Skis, jackets, trails; some earnable free | $0.99–2.99 |

**The Storm Archive** is a permanent, growing catalog of real historic weather events —
Chamonix Feb 2021, the day snow fell on the Sahara. Each is a weather record plus a curated
seed, so new items cost almost nothing to author, and each carries its own isolated
leaderboard. Buying a storm grants a new place to compete, never an advantage where you
already compete.

Full Archive replaces the season pass: whale LTV in one payment, permanent value delivery,
no FOMO, no live-ops calendar (ADR-007).

## Art direction

**Atmospheric Realism.** Soft volumetric light, aerial perspective, particle-heavy snow,
film grain.

The palette is a *function*, not a folder. `PaletteGenerator` computes every colour in
OKLCH from sun altitude, cloud cover, precipitation, and snow state. An overcast dawn in
falling snow and clear alpine noon are two evaluations of one expression. This is the only
approach that scales: weather is continuous, so any finite set of authored backdrops would
either quantise it or fail to cover it.

Shadowed snow takes the sky's hue rather than grey — that single detail is most of what
separates convincing snow from muddy snow.

## Non-goals

Deliberately not built. Recorded so they stop being re-proposed: season pass, gem currency,
interstitial ads, pay-to-win of any kind, real-money wagering, real-time multiplayer racing.
