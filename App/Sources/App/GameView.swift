import SwiftUI
import SpriteKit
import WhiteoutCore

@main
struct WhiteoutApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .statusBarHidden()
                .preferredColorScheme(.dark)
        }
    }
}

struct GameView: View {
    @State private var store = ConditionsStore()
    @State private var telemetry = RunTelemetry()
    @State private var sceneID = UUID()
    @State private var showDevTools = false

    var body: some View {
        // The reader deliberately keeps its safe area, which is the only way
        // `safeAreaInsets` reports real numbers — applying `ignoresSafeArea` above it
        // zeroes them, and the readouts end up under the Dynamic Island.
        //
        // So the split is: overlays inherit the inset region for free, and only the canvas
        // opts out of it. The scene is handed the reconstructed full display size, because
        // it is built once from that size and would otherwise place the horizon against a
        // rectangle narrower than the screen it renders into.
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let displaySize = CGSize(
                width: geometry.size.width + insets.leading + insets.trailing,
                height: geometry.size.height + insets.top + insets.bottom
            )

            ZStack(alignment: .topLeading) {
                SpriteView(scene: makeScene(size: displaySize))
                    .id(sceneID)
                    .ignoresSafeArea()

                overlays
            }
        }
        .task { await reload() }
    }

    private var overlays: some View {
        ZStack(alignment: .topLeading) {
            RunHUD(telemetry: telemetry, physics: store.conditions.physics)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
                .allowsHitTesting(false)

            ConditionsCard(conditions: store.conditions, usingFallback: store.usingFallback)
                .padding(20)

            // Location and elevation pickers are development scaffolding. Four
            // competing elements do not fit a 402pt-tall landscape screen, and
            // leaving them always-visible hid the game's actual layout behind
            // tools that will not ship.
            DevPanel(
                isExpanded: $showDevTools,
                origin: store.origin,
                peak: store.peak,
                unlockedPeaks: store.unlockedPeaks,
                onSelectOrigin: { origin in
                    store.origin = origin
                    Task { await reload() }
                },
                onSelectPeak: { peak in
                    store.peak = peak
                    Task { await reload() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(20)

            // Bottom-trailing keeps it clear of all three of the conditions card, the run
            // HUD and the dev panel — and, more importantly, away from where a thumb rests
            // to hold the tuck.
            MuteButton()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(20)
        }
    }

    private func makeScene(size: CGSize) -> MountainScene {
        // SpriteView caches by identity, so the scene is rebuilt only when `sceneID`
        // changes — i.e. when new conditions arrive, not on every SwiftUI re-render.
        let scene = MountainScene(conditions: store.conditions, telemetry: telemetry, size: size)
        scene.scaleMode = .resizeFill
        return scene
    }

    private func reload() async {
        await store.load()
        sceneID = UUID()
    }
}

/// The conditions readout. Written in ski-report register, not marketing register.
struct ConditionsCard: View {
    let conditions: RunConditions
    let usingFallback: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conditions.placeName.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.62))

            Text(conditions.snowState.displayName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(conditions.snowState.reportLine)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: 14) {
                Readout(value: "\(Int(conditions.weather.temperatureC.rounded()))°", label: "TEMP")
                Readout(value: "\(Int(conditions.weather.freshSnowCm))cm", label: "NEW")
                Readout(value: "\(Int(conditions.weather.windSpeedKmh))", label: "WIND")
                Readout(value: visibilityText, label: "VIS")
            }
            .padding(.top, 6)

            if usingFallback {
                Text("offline · default conditions")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var visibilityText: String {
        let metres = conditions.weather.visibilityM
        return metres >= 1_000 ? "\(Int(metres / 1_000))km" : "\(Int(metres))m"
    }

    private struct Readout: View {
        let value: String
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

/// Live run readout.
///
/// The edge meter is the important element. Instability is invisible in the world — the
/// skier looks fine right up until they do not — so without a readout the player cannot
/// learn *why* a two-second tuck is fine on powder and fatal on boilerplate. The meter is
/// what turns the snowpack from a hidden stat into a decision the player makes knowingly.
struct RunHUD: View {
    let telemetry: RunTelemetry
    let physics: SnowPhysics

    var body: some View {
        VStack(spacing: 10) {
            if telemetry.hasCrashed {
                VStack(spacing: 3) {
                    Text("CAUGHT AN EDGE")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(2.4)
                    Text("tap to drop in again")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.65)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.4), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("\(Int(telemetry.distanceM))m")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("\(Int(telemetry.speedKmh)) km/h")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.7)
                if telemetry.flips > 0 {
                    Text("×\(telemetry.flips) flip")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 1)

            EdgeMeter(value: telemetry.instability, chatter: physics.chatter)
        }
    }

    private struct EdgeMeter: View {
        let value: Double
        /// Surface roughness, shown as the meter's own fill rate.
        let chatter: Double

        var body: some View {
            VStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule()
                        .fill(colour)
                        .frame(width: max(2, 168 * value))
                }
                .frame(width: 168, height: 5)

                Text("EDGE")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .animation(.linear(duration: 0.08), value: value)
        }

        /// Green through amber to red. The colour is the warning; the player should never
        /// have to read a number to know they have pushed the tuck too far.
        private var colour: Color {
            switch value {
            case ..<0.55: .green.opacity(0.85)
            case ..<0.82: .yellow.opacity(0.9)
            default: .red
            }
        }
    }
}

/// Silences the procedural wind and edge noise.
///
/// Unlike the dev panel this one ships. The game has no music and no voice, so the only
/// thing to silence is the synthesised weather — and a player on a train, or a developer
/// running the same slope forty times to photograph it, needs that within one tap rather
/// than buried behind a settings screen that does not exist yet (T-204).
///
/// Haptics stay live: muting is about the room, not the hand.
struct MuteButton: View {
    private var settings: AudioSettings { AudioSettings.shared }

    var body: some View {
        Button {
            settings.isMuted.toggle()
        } label: {
            Image(systemName: settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(settings.isMuted ? 0.55 : 1))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.black.opacity(0.35)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.isMuted ? "Unmute weather audio" : "Mute weather audio")
    }
}

/// Collapsible development scaffolding: jump between climates and elevations.
///
/// Collapsed by default so the shipping layout — conditions card and run HUD — is what
/// you actually see. None of this survives to the App Store.
struct DevPanel: View {
    @Binding var isExpanded: Bool
    let origin: Origin
    let peak: Peak
    let unlockedPeaks: [Peak]
    let onSelectOrigin: (Origin) -> Void
    let onSelectPeak: (Peak) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(.plain)

            if isExpanded {
                PeakPicker(selection: peak, unlocked: unlockedPeaks, onSelect: onSelectPeak)
                OriginPicker(selection: origin, onSelect: onSelectOrigin)
            }
        }
    }
}

/// Elevation selector.
///
/// Altitude is the progression axis: it is unlocked by distance skied and never sold,
/// because thinner air genuinely raises top speed and selling that would be selling power.
///
/// Locked peaks remain tappable in this prototype build so the altitude model can be
/// demonstrated; the shipping build gates them on `unlocked`.
struct PeakPicker: View {
    let selection: Peak
    let unlocked: [Peak]
    let onSelect: (Peak) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Peak.all) { peak in
                let isUnlocked = unlocked.contains(peak)
                Button {
                    onSelect(peak)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(peak.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(isUnlocked
                                 ? "\(Int(peak.elevationM))m"
                                 : "\(Int(peak.unlockDistanceM / 1_000))km to unlock")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .opacity(0.6)
                        }
                        if !isUnlocked {
                            Image(systemName: "lock.fill").font(.system(size: 9))
                        }
                    }
                    .foregroundStyle(peak == selection ? .black : .white.opacity(isUnlocked ? 1 : 0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(peak == selection ? .white : .white.opacity(0.16))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Dev affordance for stepping through climates without leaving the country.
struct OriginPicker: View {
    let selection: Origin
    let onSelect: (Origin) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Group {
                ForEach(Origin.showcase) { origin in
                    Button {
                        onSelect(origin)
                    } label: {
                        Text(origin.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(selection == origin ? .black : .white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selection == origin ? .white : .white.opacity(0.16))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
