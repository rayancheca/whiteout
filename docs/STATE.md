# State

**Updated:** Session 0004 · 2026-08-05
**Milestone:** M1 (Vertical Slice) — T-113 closed as not-a-defect, T-112 done, T-115 added

---

## Where the project is

**111 tests passing** across 16 suites in ~30 ms. iOS build green. Working tree clean,
**8 commits ahead of `origin/main` and not yet pushed** — see "The push" below.

T-112 is **done**. All eight README beats are recaptured, fullscreen, against live
Open-Meteo data, with the real skier rig. T-113 turned out not to be a bug at all.

## T-113 was never a defect

**The tuck renders. It always did.** The app is fine; the *measurement* was wrong, in two
independent ways, and neither is visible from a transcript:

1. **A hold call returns after touch-up.** So a screenshot taken on the next line always
   photographs the released, upright pose. The pose can only ever look unchanged. The
   capture has to run *concurrently* with the hold — background the screenshot, issue the
   touch in the same batch.
2. **The app under test was a stale process**, frozen at 894 m / 0 km/h from a previous
   session. A frozen SpriteKit app photographs exactly like a live one ignoring input. This
   is also what produced Session 0003's "speed only drifted 61 → 63 km/h over a 15 s press".

Against a freshly launched app, one sustained `touch_path` took the skier **43 → 71 →
80 km/h**, tuck rendered throughout, EDGE meter climbing. No code was changed, because
nothing was broken. Recorded as **ADR-023**.

The user confirmed by hand at the start of the session that holding does tuck the skier on
the simulator — that one answer is what split the cause in a single step. Ask it early.

**Session 0003's environment note is wrong and has been corrected: `touch_path` *does*
sustain a touch.**

## The README now

Eight beats in `docs/screenshots/`, all 2622 × 1206 downscaled to 1748 px, all verified
free of the dev panel by a pixel check:

| Beat | Capture | Reading |
|------|---------|---------|
| 1 | Chamonix | Spring Slush · 10° · 17 km |
| 2 | Reykjavík | Boilerplate · −6° · 35 km/h · 25 km |
| 3 | Tokyo @ 2,800 m | Spring Slush · 5° · 3 km · night · 197 m @ 58 km/h |
| 4 | Tokyo @ 5,200 m | Packed · −10° · **4 cm new** · 238 m @ 78 km/h |
| 5 | Carving | Chamonix slush · 894 m @ 60 km/h |
| 6 | **Tucked** | Chamonix slush · 1,276 m @ 72 km/h — first ever capture of the tuck |
| 7 | Atmosphere | Reykjavík · Packed · 25 km |
| 8 | Crash | collapsed on the slope, EDGE full red |

Beats 3 and 4 were **reshot this session**: the pending versions had the dev panel open,
one with a *locked* peak selected directly beneath a caption about peaks unlocking by
distance. Beats 5 and 6 are the first captures of either state with the real rig.

The 3/4 pairing is the strongest thing in the README: same weather, same moment, 2,400 m
apart — 5 °C slush becomes −10 °C packed, **0 cm new becomes 4 cm** because up there the
same precipitation falls as snow, and top speed goes 58 → 78 km/h on thinner air.

## T-115 — mute button (new, done)

Requested mid-session. One tap silences the synthesised wind and edge noise; bottom-trailing
so it clears the card, the HUD, the dev panel, and a resting thumb.

Lives in a shared `AudioSettings`, **not** on the scene: `GameView` builds a fresh
`MountainScene` every body evaluation while `SpriteView` keeps presenting the old one until
`sceneID` changes, so a flag passed at construction lands on a scene nobody sees. Muting
zeroes the gains rather than stopping the engine — no restart click. Haptics untouched.
Persists across relaunch. T-204 should absorb it into a real settings screen.

## The push

`T-112` says "then push", and its pre-publish gate is now satisfied — eight live captures
with real data. **The push was not performed**, because publishing to a public repo is the
user's call and was not asked for this session. It is a one-line action whenever wanted.

## Still unverified

- **Haptics and procedural audio.** No taptic engine in the simulator. Needs T-109. The
  mute button's *audio* path was verified on the simulator; its haptic non-interference was
  reasoned from the code, not measured.
- **Landscape-right safe area.** Landscape-left only, still.
- **Mid-blend bone rigidity (T-111).** `blended(toward:amount:)` shortens bones at
  intermediate `t`. Still unobservable on screen: `tuckCompression` is binary, so no
  intermediate `t` is ever drawn.

## Environment notes

- **`touch_path` sustains a touch.** Repeated identical points spaced by `dt_ms`. Screenshot
  it *concurrently* — a backgrounded `sleep N && xcrun simctl io booted screenshot` issued in
  the same tool batch as the touch.
- **Confirm the app is actually ticking before measuring anything.** Two captures a few
  seconds apart; if distance and speed are identical, it is a stale process, not a bug.
  Relaunch with `xcrun simctl terminate/launch booted com.whiteout.game`.
- The build lands in `./build/Build/Products/Debug-iphonesimulator/Whiteout.app`
  (`verify.sh` passes `-derivedDataPath build`), **not** DerivedData.
- **`timeout` does not exist on macOS.** Use `gtimeout` or no wrapper.
- Screenshots need `sips -r -90`; device portrait, app landscape.
- Dev panel taps in device points (402 × 874): gear `(366, 776)`, Chamonix `(108, 749)`,
  Reykjavík `(71, 750)`, Tokyo `(35, 760)`, The Resort `(322, 747)`, Thin Air `(188, 738)`,
  mute `(56, 775)`. Miami is clipped off the bottom of the picker and is not tappable.
- A cold launch can resolve to `offline · default conditions`; re-selecting an origin in the
  dev panel forces a live re-resolve.

## Next

**T-102 — skier animation states** is the largest remaining M1 item and is unblocked.
T-111 (rig blending in angle space) is worth pairing with it, since T-102 will introduce the
intermediate blend values that make T-111's bone shortening visible for the first time.

T-103 and T-106 remain unblocked and independent. T-114 (`GameView` rebuilding the scene
every body evaluation) is small, real, and was last session's prime suspect — worth clearing
so it never misleads anyone again.
