import Foundation

/// Deterministic, *indexed* pseudo-random source.
///
/// Unlike a conventional generator, this exposes no sequence cursor: every value is a
/// pure function of `(seed, index)`. That property is what makes the whole game
/// reproducible — terrain chunk 5,000 can be generated without first generating chunks
/// 0…4,999, so a replay, a ghost, and a fresh run all agree without any shared state.
///
/// Algorithm is SplitMix64, chosen for excellent avalanche behaviour on sequential
/// indices (the exact access pattern terrain generation uses).
public struct SeededRandom: Sendable, Equatable {

    /// Fractional part of the golden ratio, scaled to 64 bits. Standard SplitMix64 increment.
    private static let goldenGamma: UInt64 = 0x9E37_79B9_7F4A_7C15

    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    /// Derives a seed from an arbitrary string (a storm slug, a date key, a geohash).
    public init(key: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a offset basis
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3 // FNV prime
        }
        self.seed = hash
    }

    // MARK: - Primitives

    /// Raw 64-bit value at `index`. Pure: same inputs always yield the same output.
    public func raw(at index: UInt64) -> UInt64 {
        var z = seed &+ (index &+ 1) &* Self.goldenGamma
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in `0..<1`.
    public func unit(at index: UInt64) -> Double {
        // Top 53 bits give exactly the mantissa precision of Double, avoiding bias.
        Double(raw(at: index) >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform value in the closed range `bounds`.
    public func value(in bounds: ClosedRange<Double>, at index: UInt64) -> Double {
        bounds.lowerBound + unit(at: index) * (bounds.upperBound - bounds.lowerBound)
    }

    /// Uniform integer in the closed range `bounds`.
    public func integer(in bounds: ClosedRange<Int>, at index: UInt64) -> Int {
        let span = UInt64(bounds.upperBound - bounds.lowerBound + 1)
        return bounds.lowerBound + Int(raw(at: index) % span)
    }

    /// `true` with probability `probability`.
    public func chance(_ probability: Double, at index: UInt64) -> Bool {
        unit(at: index) < probability
    }

    /// Returns a new generator whose stream is independent of this one.
    ///
    /// Used to keep subsystems from interfering: terrain, weather events and prop
    /// placement each take their own domain so adding a feature to one never shifts
    /// the output of another.
    public func domain(_ name: String) -> SeededRandom {
        SeededRandom(seed: seed ^ SeededRandom(key: name).seed)
    }

    // MARK: - Continuous noise

    /// Smooth 1D value noise in `-1...1`, sampled at continuous position `x`.
    ///
    /// Uses a quintic fade (Perlin's improved curve) so the second derivative is
    /// continuous — first-derivative-only smoothing produces visible creases in a
    /// terrain silhouette at low speed.
    public func noise(at x: Double) -> Double {
        let cell = x.rounded(.down)
        let t = x - cell
        let index = UInt64(bitPattern: Int64(cell))

        let a = unit(at: index) * 2 - 1
        let b = unit(at: index &+ 1) * 2 - 1

        let fade = t * t * t * (t * (t * 6 - 15) + 10)
        return a + (b - a) * fade
    }

    /// Fractal Brownian motion: layered `noise` at doubling frequency and decaying amplitude.
    ///
    /// Produces the self-similar ridgeline structure real mountains have — broad shoulders
    /// from low octaves, moguls and chatter from high ones.
    public func fbm(
        at x: Double,
        octaves: Int = 4,
        frequency: Double = 1,
        persistence: Double = 0.5,
        lacunarity: Double = 2
    ) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var currentFrequency = frequency
        var normalisation = 0.0

        for octave in 0..<max(1, octaves) {
            // Offsetting each octave keeps them from aligning at x = 0, which would
            // otherwise stack every peak into one artificial spike at the origin.
            let offset = Double(octave) * 137.51
            total += noise(at: x * currentFrequency + offset) * amplitude
            normalisation += amplitude
            amplitude *= persistence
            currentFrequency *= lacunarity
        }

        return normalisation > 0 ? total / normalisation : 0
    }
}
