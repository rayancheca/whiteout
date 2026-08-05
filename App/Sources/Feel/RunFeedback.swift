import AVFoundation
import CoreHaptics
import WhiteoutCore

/// Haptics and audio for a run.
///
/// Both channels are synthesised, not sampled. Wind and edge noise are filtered white
/// noise whose gain and colour come straight from `FeelCues`, which means the soundtrack
/// responds continuously to the real weather instead of crossfading between a handful of
/// recorded loops. It also ships zero audio assets.
///
/// Every failure path here is silent by design: a device without haptics, a denied audio
/// session, or an engine that will not start must never stop the game rendering.
@MainActor
final class RunFeedback {

    // MARK: Haptics

    private var hapticEngine: CHHapticEngine?
    private var chatterPlayer: CHHapticAdvancedPatternPlayer?

    // MARK: Audio

    private let engine = AVAudioEngine()
    private let windMixer = AVAudioMixerNode()
    private let carveMixer = AVAudioMixerNode()

    private let parameters = AudioParameters()
    private var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startHaptics()
        startAudio()
    }

    func stop() {
        isRunning = false
        try? chatterPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticEngine?.stop()
        engine.stop()
    }

    // MARK: - Per-frame

    func update(cues: FeelCues, delta: Double) {
        // Muting zeroes the gains rather than stopping the engine: the render block keeps
        // running and the sound resumes on the next frame after unmuting, with no restart
        // click and no torn-down audio session. Haptics are deliberately unaffected —
        // "mute" is about what the room hears.
        let audible: Float = AudioSettings.shared.isMuted ? 0 : 1
        parameters.windGain.pointee = Float(cues.windLevel) * 0.16 * audible
        parameters.carveGain.pointee = Float(cues.carveLevel) * 0.13 * audible

        // Surface roughness as a continuous rumble. This is the channel that makes the
        // snowpack a physical fact rather than a label on a card — the player feels
        // boilerplate through their hand before reading the word.
        guard let chatterPlayer else { return }
        let intensity = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: Float(cues.shake),
            relativeTime: 0
        )
        let sharpness = CHHapticDynamicParameter(
            parameterID: .hapticSharpnessControl,
            // Rougher surfaces are sharper as well as stronger.
            value: Float(0.3 + cues.shake * 0.6),
            relativeTime: 0
        )
        try? chatterPlayer.sendParameters([intensity, sharpness], atTime: CHHapticTimeImmediate)
    }

    func landing(strength: Double) {
        playTransient(intensity: Float(0.35 + strength * 0.6), sharpness: 0.55)
    }

    func crash() {
        playTransient(intensity: 1, sharpness: 0.25)
    }

    // MARK: - Haptics setup

    private func startHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // The system stops the engine on interruption; without this the rumble is
            // simply gone for the rest of the session.
            engine.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            try engine.start()
            hapticEngine = engine

            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0,
                // Long-lived and modulated by dynamic parameters, rather than restarted
                // each frame — restarting produces audible clicks in the taptic engine.
                duration: 60 * 60
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            chatterPlayer = player
        } catch {
            hapticEngine = nil
            chatterPlayer = nil
        }
    }

    private func playTransient(intensity: Float, sharpness: Float) {
        guard let hapticEngine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? hapticEngine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    // MARK: - Audio setup

    private func startAudio() {
        // Ambient and mixable: a casual game has no business stopping the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let format = engine.outputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        let wind = Self.makeNoiseNode(
            format: format, gain: parameters.windGain, smoothing: 0.06, isHighPass: false
        )
        let carve = Self.makeNoiseNode(
            format: format, gain: parameters.carveGain, smoothing: 0.55, isHighPass: true
        )

        for (source, mixer) in [(wind, windMixer), (carve, carveMixer)] {
            engine.attach(source)
            engine.attach(mixer)
            engine.connect(source, to: mixer, format: format)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)
        }

        do {
            try engine.start()
        } catch {
            engine.stop()
        }
    }

    /// A filtered-white-noise generator.
    ///
    /// One-pole filter: low-passed noise is the rumble of moving air, and the high-passed
    /// residue is the hiss of an edge on snow. Two settings of the same three lines cover
    /// both, which is why this needs no audio files at all.
    ///
    /// `nonisolated` is load-bearing, not decorative. As a static member of a `@MainActor`
    /// type this inherits main-actor isolation, and the render block then calls
    /// `swift_task_checkIsolatedSwift` on the real-time audio thread — which traps with
    /// SIGTRAP the instant audio starts. The isolation is invisible at the call site and
    /// the crash lands in libdispatch, so it reads as an AVFoundation fault rather than a
    /// concurrency one.
    private nonisolated static func makeNoiseNode(
        format: AVAudioFormat,
        gain: UnsafeMutablePointer<Float>,
        smoothing: Float,
        isHighPass: Bool
    ) -> AVAudioSourceNode {
        // Filter memory and RNG state are owned by a box captured by the render block, so
        // nothing is allocated while audio runs and everything is freed when the node is.
        let state = NoiseState()

        return AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let level = gain.pointee

            for frame in 0..<Int(frameCount) {
                // xorshift32 — cheap, allocation-free, and good enough for noise.
                var seed = state.random.pointee
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                state.random.pointee = seed

                let white = Float(seed % 20_001) / 10_000 - 1
                let filtered = state.filter.pointee + smoothing * (white - state.filter.pointee)
                state.filter.pointee = filtered

                let sample = (isHighPass ? white - filtered : filtered) * level

                for buffer in buffers {
                    let channel = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < channel.count { channel[frame] = sample }
                }
            }
            return noErr
        }
    }
}

/// Gain values written from the main thread and read on the audio render thread.
///
/// Deliberately not actor-isolated. The render block must never allocate, lock, or enter
/// the Swift runtime, so the parameters it reads have to be plain memory — and an
/// isolated type cannot free that memory from `deinit` under strict concurrency.
private final class AudioParameters: @unchecked Sendable {
    let windGain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let carveGain = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    init() {
        windGain.initialize(to: 0)
        carveGain.initialize(to: 0)
    }

    deinit {
        windGain.deallocate()
        carveGain.deallocate()
    }
}

/// Per-generator filter memory and RNG state, owned for the lifetime of its source node.
private final class NoiseState: @unchecked Sendable {
    let filter = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let random = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)

    init() {
        filter.initialize(to: 0)
        random.initialize(to: 0x9E37_79B9)
    }

    deinit {
        filter.deallocate()
        random.deallocate()
    }
}
