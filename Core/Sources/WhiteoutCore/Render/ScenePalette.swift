import Foundation

/// Every colour the renderer needs for one run, derived from that run's weather.
public struct ScenePalette: Sendable, Equatable {
    public let skyZenith: OKLCH
    public let skyHorizon: OKLCH
    /// Colour of the atmosphere itself — distant geometry converges to this.
    public let atmosphere: OKLCH
    /// Direct light colour; also tints sunlit snow.
    public let light: OKLCH
    public let snowLit: OKLCH
    public let snowShadow: OKLCH
    public let rockNear: OKLCH
    /// The skier's body. Dark, and tied to the snow it is seen against.
    public let skierBody: OKLCH
    /// Light catching the skier's leading edges. Carries the read when the body cannot.
    public let skierRim: OKLCH
    /// `0...1`. How completely distance dissolves geometry into atmosphere.
    public let depthDissolve: Double
    /// `0...1`. Overall scene brightness, for exposure and UI contrast decisions.
    public let exposure: Double
}

extension ScenePalette {

    /// A distant ridge band, tinted toward the atmosphere in proportion to its depth.
    ///
    /// Lives here rather than in the renderer because it is the surface the skier is drawn
    /// against, so the legibility guarantee has to be able to compute it. Keeping a second
    /// copy in the scene is how the two quietly drift apart.
    public func ridge(depth: Double) -> OKLCH {
        rockNear.blended(toward: atmosphere, amount: min(0.98, depthDissolve * depth))
    }

    /// The lit upper face of a ridge band.
    ///
    /// Real ridges catch light along the top and sink into shadow at the base. A single flat
    /// colour per band is the tell that reads as clip-art.
    public func ridgeCrest(depth: Double) -> OKLCH {
        ridge(depth: depth).blended(toward: snowLit, amount: 0.28 * (1 - depth * 0.5))
    }

    /// The shadowed base of a ridge band.
    public func ridgeBase(depth: Double) -> OKLCH {
        ridge(depth: depth).blended(toward: OKLCH(l: 0, c: 0, h: rockNear.h), amount: 0.22)
    }

    /// Depth of the nearest parallax band — the one the skier's body actually overlaps.
    ///
    /// Measured from the scene's own layout: the skier stands at 0.34 of screen height and
    /// tops out near 0.42, while this band fills everything below 0.55. Reaching the sky
    /// would take about 111 m of relative altitude, which no jump in the game produces. So
    /// the sky is not a backdrop the skier is ever seen against, and testing contrast
    /// against it measures nothing.
    public static let skierBackdropDepth = 0.42
}

/// Generates the scene palette from mountain weather.
///
/// The art direction is a function, not a folder of assets. There is no "storm sky"
/// texture and no "dusk" variant: an overcast dawn in falling snow and a clear alpine noon
/// are two evaluations of the same expression. That is the only way this scales — the
/// weather has a continuous range of states, so any finite set of authored backdrops would
/// either quantise the weather or fail to cover it.
public enum PaletteGenerator {

    public static func palette(for weather: MountainWeather, state: SnowState) -> ScenePalette {
        let sun = weather.sunAltitudeDeg
        let cloud = min(max(weather.cloudCoverPercent / 100, 0), 1)

        let baseZenith = zenith(sunAltitude: sun)
        let baseHorizon = horizon(sunAltitude: sun)
        let lightColour = light(sunAltitude: sun)

        // Overcast is desaturation plus contrast compression, not simple darkening —
        // multiple scattering between cloud and snow actually *raises* horizon luminance
        // while draining hue, which is why a snowy overcast day reads as flat and bright.
        let overcastGrey = OKLCH(l: 0.74, c: 0.012, h: 250)
        let zenithColour = baseZenith.blended(toward: overcastGrey.withLightness(baseZenith.l * 0.55 + 0.30), amount: cloud * 0.82)
        let horizonColour = baseHorizon.blended(toward: overcastGrey.withLightness(baseHorizon.l * 0.45 + 0.42), amount: cloud * 0.88)

        // Visibility is the physical driver of aerial perspective. Falling snow collapses
        // it, which is exactly what should flatten the mountain into layered silhouettes.
        let visibilityFactor = 1 - min(max(weather.visibilityM / 4_000, 0), 1)
        // The floor is high on purpose. Aerial perspective does not switch off in clear
        // air — a ridge 20 km away is visibly paler than one 2 km away even on the
        // sharpest day. An earlier floor of 0.16 left all three parallax bands within a
        // few percent of each other, which flattened the range into one dark silhouette.
        let dissolve = min(0.97, 0.34 + visibilityFactor * 0.62)

        let atmosphere = horizonColour
            .blended(toward: OKLCH(l: 0.88, c: 0.006, h: 250), amount: visibilityFactor * 0.7)

        let exposure = min(1, max(0.08, sunExposure(sunAltitude: sun) * (1 - cloud * 0.30)))

        let lit = snowLit(state: state, light: lightColour, cloud: cloud, exposure: exposure)
        let shadow = snowShadow(zenith: zenithColour, exposure: exposure)

        return ScenePalette(
            skyZenith: zenithColour,
            skyHorizon: horizonColour,
            atmosphere: atmosphere,
            light: lightColour.desaturated(by: cloud * 0.65),
            snowLit: lit,
            snowShadow: shadow,
            rockNear: OKLCH(l: 0.22 + exposure * 0.10, c: 0.018, h: 262),
            skierBody: skierBody(snowShadow: shadow, zenith: zenithColour, exposure: exposure),
            skierRim: skierRim(snowLit: lit, exposure: exposure),
            depthDissolve: dissolve,
            exposure: exposure
        )
    }

    // MARK: - The skier
    //
    // The skier is the one object that must stay legible in *every* palette, and no single
    // tone manages it. The backdrop it is drawn against is the nearest ridge band, whose
    // lightness runs from about 0.25 at night to 0.59 at noon — the *middle* of the axis.
    // The one place you cannot afford to be is near the middle, and anything anchored to
    // `rockNear` lands there: `rockNear.l` spans only 0.228…0.320 while its backdrop spans
    // 0.25…0.59, so it crosses straight through it. The old fill measured a separation of
    // 0.02 against the near ridge at night, which is roughly one 8-bit code value.
    //
    // So the skier is drawn in two tones pinned near opposite ends of the lightness axis.
    // Whatever the backdrop does, one of them is far from it. Hue and chroma still come from
    // the weather, so the skier belongs to the day; only lightness is pinned.

    /// Minimum perceptual lightness gap the skier must hold against its backdrop.
    ///
    /// Enforced by test rather than by intention — the palette is a continuous function of
    /// weather, so the only way to know this holds everywhere is to assert it.
    public static let skierContrastFloor = 0.20

    private static func skierBody(snowShadow: OKLCH, zenith: OKLCH, exposure: Double) -> OKLCH {
        // Deliberately almost flat across the whole weather range: this is the dark end of
        // the axis and its job is to stay there. Floored above zero because a true black
        // silhouette reads as a hole punched in the scene rather than as a person.
        OKLCH(
            l: 0.095 + exposure * 0.050,
            // A skier in shadow is lit by skylight exactly as the snow is, so the body takes
            // the sky's hue — a very dark indigo rather than a neutral. Muted, because
            // fabric is nothing like as reflective as snow.
            c: min(0.045, snowShadow.c * 0.55 + 0.010),
            h: zenith.h
        )
    }

    private static func skierRim(snowLit: OKLCH, exposure: Double) -> OKLCH {
        // A rim is specular — it is the light source seen in an edge — so unlike `snowLit`
        // it is not bound by exposure. As the scene darkens the rim climbs *further* above
        // the snow, which is both physically right and the only thing that keeps the player
        // findable at night. Held short of white so it reads as a lit edge and not as glow.
        snowLit.blended(
            toward: OKLCH(l: 1, c: 0, h: snowLit.h),
            amount: 0.35 + 0.30 * (1 - exposure)
        )
    }

    // MARK: - Solar model
    //
    // Keyframes are placed at the transitions a photographer would name — astronomical
    // night, civil twilight, sunrise, golden hour, full day — and interpolated between,
    // so the sky moves continuously through them instead of snapping between presets.

    private static func zenith(sunAltitude: Double) -> OKLCH {
        keyframe(
            sunAltitude,
            stops: [
                (-18, OKLCH(l: 0.11, c: 0.038, h: 276)), // astronomical night
                (-6, OKLCH(l: 0.24, c: 0.072, h: 282)),  // civil twilight
                (0, OKLCH(l: 0.46, c: 0.086, h: 268)),   // sunrise
                (8, OKLCH(l: 0.62, c: 0.098, h: 252)),   // low sun
                (30, OKLCH(l: 0.70, c: 0.115, h: 240)),  // mid morning
                (65, OKLCH(l: 0.74, c: 0.128, h: 236))   // alpine noon
            ]
        )
    }

    private static func horizon(sunAltitude: Double) -> OKLCH {
        keyframe(
            sunAltitude,
            stops: [
                (-18, OKLCH(l: 0.15, c: 0.030, h: 284)),
                (-6, OKLCH(l: 0.38, c: 0.105, h: 32)),   // the warm band under a cold sky
                (0, OKLCH(l: 0.66, c: 0.155, h: 46)),    // sunrise/sunset
                (8, OKLCH(l: 0.83, c: 0.088, h: 74)),    // golden hour
                (30, OKLCH(l: 0.89, c: 0.036, h: 210)),
                (65, OKLCH(l: 0.90, c: 0.030, h: 228))
            ]
        )
    }

    private static func light(sunAltitude: Double) -> OKLCH {
        keyframe(
            sunAltitude,
            stops: [
                (-18, OKLCH(l: 0.30, c: 0.040, h: 268)), // moonlight reads cool and dim
                (-6, OKLCH(l: 0.48, c: 0.060, h: 300)),
                (0, OKLCH(l: 0.78, c: 0.140, h: 52)),
                (8, OKLCH(l: 0.90, c: 0.100, h: 78)),
                (30, OKLCH(l: 0.97, c: 0.030, h: 96)),
                (65, OKLCH(l: 0.99, c: 0.014, h: 100))
            ]
        )
    }

    private static func sunExposure(sunAltitude: Double) -> Double {
        switch sunAltitude {
        case ..<(-12): 0.10
        case ..<0: 0.10 + (sunAltitude + 12) / 12 * 0.32
        case ..<20: 0.42 + sunAltitude / 20 * 0.44
        default: min(1, 0.86 + (sunAltitude - 20) / 45 * 0.14)
        }
    }

    // MARK: - Surface

    private static func snowLit(
        state: SnowState,
        light: OKLCH,
        cloud: Double,
        exposure: Double
    ) -> OKLCH {
        // Snow is a near-perfect diffuse reflector, so lit snow is essentially the light
        // source's own colour. Surface state modulates it only slightly — but that slight
        // shift is real and readable: ice is glassier and darker, slush greyer and wetter.
        let base = OKLCH(l: 0.93 * (0.55 + exposure * 0.45), c: light.c * 0.32, h: light.h)
        switch state {
        case .powder: return base.withLightness(min(1, base.l * 1.04))
        case .packed: return base
        case .crust: return base.withLightness(base.l * 0.97).withChroma(base.c * 0.85)
        case .slush: return base.withLightness(base.l * 0.90).withChroma(base.c * 0.70)
        case .ice: return base.withLightness(base.l * 0.87).withChroma(base.c * 1.25)
        case .windSlab: return base.withLightness(base.l * 0.95)
        }
    }

    private static func snowShadow(zenith: OKLCH, exposure: Double) -> OKLCH {
        // Shadowed snow is lit almost entirely by skylight, so it takes the sky's hue.
        // This is why alpine shadows photograph blue, and getting it right is most of
        // what separates convincing snow from grey snow.
        OKLCH(
            l: 0.34 + exposure * 0.30,
            c: zenith.c * 1.15,
            h: zenith.h
        )
    }

    // MARK: - Interpolation

    /// Piecewise-linear interpolation across `stops`, clamped at both ends.
    private static func keyframe(_ input: Double, stops: [(Double, OKLCH)]) -> OKLCH {
        guard let first = stops.first, let last = stops.last else {
            return OKLCH(l: 0.5, c: 0, h: 0)
        }
        if input <= first.0 { return first.1 }
        if input >= last.0 { return last.1 }

        for index in 0..<(stops.count - 1) {
            let (lowerBound, lowerColour) = stops[index]
            let (upperBound, upperColour) = stops[index + 1]
            if input >= lowerBound && input <= upperBound {
                let span = upperBound - lowerBound
                let t = span > 0 ? (input - lowerBound) / span : 0
                return lowerColour.blended(toward: upperColour, amount: t)
            }
        }
        return last.1
    }
}
