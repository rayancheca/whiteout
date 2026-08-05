import Foundation

/// A colour in OKLCH: perceptual lightness, chroma, hue.
///
/// The palette is *computed* from weather rather than hand-authored, which means the app
/// interpolates colours constantly — every frame at dawn, every change in cloud cover.
/// Interpolating in sRGB produces the muddy grey midpoints that make procedural skies look
/// cheap, because sRGB is not perceptually uniform. Oklab is, so a blend between two colours
/// passes through the hues an artist would have picked, and equal steps in `l` look equally
/// different. Matching the project's token convention, this is the authoring space; sRGB is
/// only ever the output format.
public struct OKLCH: Sendable, Equatable {

    /// Perceptual lightness, `0` (black) to `1` (white).
    public let l: Double
    /// Chroma — saturation, unbounded in principle but ~0.37 at sRGB gamut edge.
    public let c: Double
    /// Hue angle in degrees.
    public let h: Double
    /// Alpha, `0...1`.
    public let alpha: Double

    public init(l: Double, c: Double, h: Double, alpha: Double = 1) {
        self.l = l
        self.c = c
        self.h = h
        self.alpha = alpha
    }

    /// Linear interpolation toward `other`, taking the shortest path around the hue circle.
    ///
    /// The shortest-path rule matters at the day/night boundary: a naive blend from a
    /// hue of 260° to 20° sweeps backwards through green, producing a sunset that briefly
    /// turns the sky pistachio.
    public func blended(toward other: OKLCH, amount: Double) -> OKLCH {
        let t = min(max(amount, 0), 1)

        var hueDelta = other.h - h
        if hueDelta > 180 { hueDelta -= 360 }
        if hueDelta < -180 { hueDelta += 360 }

        return OKLCH(
            l: l + (other.l - l) * t,
            c: c + (other.c - c) * t,
            h: (h + hueDelta * t).truncatingRemainder(dividingBy: 360),
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    public func withLightness(_ newL: Double) -> OKLCH {
        OKLCH(l: min(max(newL, 0), 1), c: c, h: h, alpha: alpha)
    }

    public func withChroma(_ newC: Double) -> OKLCH {
        OKLCH(l: l, c: max(newC, 0), h: h, alpha: alpha)
    }

    public func withAlpha(_ newAlpha: Double) -> OKLCH {
        OKLCH(l: l, c: c, h: h, alpha: min(max(newAlpha, 0), 1))
    }

    /// Scales chroma — used to wash colour out under heavy cloud, where the physical
    /// effect of multiple scattering is genuinely desaturation, not darkening.
    public func desaturated(by factor: Double) -> OKLCH {
        withChroma(c * min(max(1 - factor, 0), 1))
    }
}

/// Gamma-encoded sRGB, `0...1` per channel — the form a renderer consumes.
public struct RGBA: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

extension OKLCH {

    /// Converts to gamma-encoded sRGB, clamping to gamut.
    ///
    /// Implements the standard Oklab pipeline: OKLCH → Oklab → LMS' → LMS → linear sRGB →
    /// gamma. Matrix constants are Björn Ottosson's published values.
    public var rgba: RGBA {
        let hueRadians = h * .pi / 180
        let a = c * cos(hueRadians)
        let bComponent = c * sin(hueRadians)

        // Oklab → nonlinear LMS
        let lPrime = l + 0.3963377774 * a + 0.2158037573 * bComponent
        let mPrime = l - 0.1055613458 * a - 0.0638541728 * bComponent
        let sPrime = l - 0.0894841775 * a - 1.2914855480 * bComponent

        let lCone = lPrime * lPrime * lPrime
        let mCone = mPrime * mPrime * mPrime
        let sCone = sPrime * sPrime * sPrime

        // LMS → linear sRGB
        let linearR = 4.0767416621 * lCone - 3.3077115913 * mCone + 0.2309699292 * sCone
        let linearG = -1.2684380046 * lCone + 2.6097574011 * mCone - 0.3413193965 * sCone
        let linearB = -0.0041960863 * lCone - 0.7034186147 * mCone + 1.7076147010 * sCone

        return RGBA(
            r: Self.gammaEncode(linearR),
            g: Self.gammaEncode(linearG),
            b: Self.gammaEncode(linearB),
            a: min(max(alpha, 0), 1)
        )
    }

    /// Linear → gamma-encoded sRGB transfer function.
    private static func gammaEncode(_ channel: Double) -> Double {
        let clamped = min(max(channel, 0), 1)
        let encoded = clamped <= 0.0031308
            ? clamped * 12.92
            : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        return min(max(encoded, 0), 1)
    }
}
