# State

**Updated:** Session 0001 · 2026-08-05
**Milestone:** M0 complete → M1 (Vertical Slice) begins

---

## Where the project is

Whiteout has a working, tested weather-to-physics engine and a playable prototype running
on the iOS Simulator. Real Open-Meteo data drives real snowpack physics that materially
change how the game plays. Project infrastructure for a long multi-session build is now in
place.

**85 tests passing** across 13 suites in ~30 ms. iOS build green.

## Verified working

Confirmed by running it, not by reasoning about it:

- Live Open-Meteo fetch → Altitude Translation → snow state → physics/palette/terrain.
  Cupertino at 2,800 m returned −4 °C packed; the same weather at 5,200 m returned −19 °C
  boilerplate, with a different terrain seed per peak.
- Chamonix in August → 12 °C spring slush. Reykjavík → −5 °C packed, 45 km visibility.
- Gameplay: tuck/carve, spray, ski trail, speed lines, edge meter, crash and restart.
  Observed 697 m at 69 km/h mid-tuck.
- Offline fallback when location is denied.

## Written but NOT verified

- **Haptics.** `RunFeedback` compiles and does not crash, but the simulator has no taptic
  engine. Entirely unverified until run on a physical device. Do not claim otherwise.
- **Procedural audio.** The engine starts without crashing; nobody has heard it.

Both need T-109 (device TestFlight) to confirm.

## Known rough edges

- The skier is a black capsule placeholder. Most visible gap — deliberate, since tuning
  feel against a placeholder beats tuning against art.
- Visuals are systemically correct but artistically thin: no volumetric light, no depth of
  field, no snow surface detail.
- Speed reads slightly high (~60–85 km/h). Worth a tuning pass on device.
- The location permission prompt appears before any context is given — needs onboarding.

## Surprises worth carrying forward

Three bugs this session were findable only by *running* the app, not by reasoning:

1. The skier was bouncing down the hill — launch used stale `velocityY` (0 on frame one and
   after every landing) instead of the slope's.
2. Carving was completely free on packed snow, so the game's single decision had no
   consequence. Only visible as "hits top speed while upright".
3. Audio hard-crashed with SIGTRAP because a `@MainActor` static method silently passed
   main-actor isolation into a real-time render block.

The pattern: physics and concurrency errors that reasoning missed and execution caught.
Future sessions should run the app, not just the suite.

Also measured: at a fixed 2,800 m, four of six snow states are unreachable through the
northern summer. That finding produced the Peaks system (ADR-009).

## Next

**T-101 — Skier character art + rig.** Replace the capsule with a real silhouette that
reads at speed and at small size, then T-102 for animation states.

M1 runs to T-109, an internal TestFlight build on real hardware — which is also the first
opportunity to verify haptics and audio.

## Environment notes

- Simulator: iPhone 17 Pro `10C15FE0-3D9A-40D5-9E45-C0702E906DF3`
- Simulator builds need `CODE_SIGNING_ALLOWED=NO`; no signing team configured
- The simulator has shut down unexpectedly a few times; `xcrun simctl boot <id>` and relaunch
- Screenshots must be rotated with `sips -r -90` (device portrait, app landscape)
- Vercel MCP is authorized and ready for M3
