import Foundation

/// Weather as it would be on the mountain, derived from weather where the player actually is.
public struct MountainWeather: Sendable, Equatable {
    public let elevationM: Double
    public let temperatureC: Double
    /// Depth of snow that fell in the trailing 24 h, at altitude.
    public let freshSnowCm: Double
    /// Current snowfall rate at altitude.
    public let snowfallCmPerHour: Double
    /// `true` when precipitation at altitude is falling as rain, not snow — the state
    /// that ruins a snowpack and produces crust once it refreezes.
    public let isRainingAtAltitude: Bool
    public let windSpeedKmh: Double
    public let windGustKmh: Double
    public let windDirectionDeg: Double
    public let visibilityM: Double
    public let cloudCoverPercent: Double
    public let sunAltitudeDeg: Double
    public let localHour: Double
    /// Warmest point of the trailing 24 h, at altitude. Combined with current
    /// temperature this detects the freeze–thaw cycle.
    public let maxTemperature24hC: Double
    public let minTemperature24hC: Double
}

/// Lifts a sea-level-ish city observation to alpine altitude.
///
/// This exists to solve the concept's fatal reach problem: a player in Lagos or Miami has
/// no local snow, and a game that renders their real weather gives them nothing. Instead of
/// excluding them, we take their *actual atmosphere* and ask what it would be doing at
/// 2,800 m. Rain becomes snowfall. A humid 34 °C afternoon becomes spring slush and valley
/// fog. Every player on Earth gets a real, personal, materially different mountain day.
///
/// The physics used are standard meteorology, not invented curves:
/// - environmental lapse rate for temperature,
/// - a temperature-dependent snow-to-liquid ratio for depth,
/// - a power-law wind profile for exposure gain.
public enum AltitudeTranslation {

    /// Ridge-top elevation the game is set at. High enough that most of the inhabited
    /// world translates to a genuine winter, low enough to stay believable.
    public static let mountainElevationM: Double = 2_800

    /// Environmental lapse rate, °C lost per kilometre of ascent.
    public static let lapseRateCPerKm: Double = 6.5

    /// Precipitation at altitude is treated as snow at or below this temperature.
    /// Slightly above zero because snowflakes survive a short fall through a shallow
    /// warm layer — the wet-bulb effect.
    private static let snowThresholdC: Double = 1.0

    public static func lift(
        _ observation: StationObservation,
        to elevationM: Double = mountainElevationM
    ) -> MountainWeather {
        let ascentKm = max(0, elevationM - observation.elevationM) / 1_000
        let cooling = ascentKm * lapseRateCPerKm

        let temperature = observation.temperatureC - cooling
        let maxTemperature = observation.maxTemperature24hC - cooling
        let minTemperature = observation.minTemperature24hC - cooling

        // Freezing level is an independent, directly measured check on our lapse estimate.
        // When the reported 0 °C isotherm sits below the mountain, precipitation is snow
        // regardless of what the lapse arithmetic suggests.
        let belowFreezingLevel = observation.freezingLevelM < elevationM
        let fallsAsSnow = temperature <= snowThresholdC || belowFreezingLevel

        let ratio = snowToLiquidRatio(atC: temperature)
        // mm of liquid → cm of snow: divide by 10 for mm→cm, multiply by the ratio.
        let snowfallRate = fallsAsSnow ? observation.precipitationMmPerHour * ratio / 10 : 0
        let freshSnow = fallsAsSnow ? observation.precipitation24hMm * ratio / 10 : 0

        let exposure = windExposureFactor(ascentKm: ascentKm)

        return MountainWeather(
            elevationM: elevationM,
            temperatureC: temperature,
            freshSnowCm: freshSnow,
            snowfallCmPerHour: snowfallRate,
            isRainingAtAltitude: !fallsAsSnow && observation.precipitationMmPerHour > 0.1,
            windSpeedKmh: observation.windSpeedKmh * exposure,
            windGustKmh: observation.windGustKmh * exposure,
            windDirectionDeg: observation.windDirectionDeg,
            visibilityM: visibility(observation, snowfallCmPerHour: snowfallRate),
            cloudCoverPercent: observation.cloudCoverPercent,
            sunAltitudeDeg: observation.sunAltitudeDeg,
            localHour: observation.localHour,
            maxTemperature24hC: maxTemperature,
            minTemperature24hC: minTemperature
        )
    }

    // MARK: - Components

    /// Snow-to-liquid ratio: how many centimetres of snow one centimetre of water makes.
    ///
    /// Near freezing, crystals are wet and collapse — roughly 7:1. Deep cold produces
    /// dendritic crystals that stack into far greater depth from the same water content.
    /// This is why "10 mm of precipitation" means a slushy nuisance at 0 °C and a metre
    /// of blower powder at −15 °C, and it is the reason cold cities translate to better
    /// snow than merely wet ones.
    static func snowToLiquidRatio(atC temperature: Double) -> Double {
        switch temperature {
        case ..<(-20): 18
        case ..<(-15): 20
        case ..<(-8): 15
        case ..<(-2): 12
        case ..<0: 10
        default: 7
        }
    }

    /// Wind gain from exposure with altitude, following a bounded power-law profile.
    ///
    /// Ridges accelerate flow, but the gain is capped: an unbounded multiplier turns a
    /// windy coastal city into a physically absurd 200 km/h ridge and breaks the physics
    /// downstream.
    static func windExposureFactor(ascentKm: Double) -> Double {
        min(2.2, 1 + ascentKm * 0.42)
    }

    /// Visibility at altitude, reduced by active snowfall.
    ///
    /// Heavy snow is the dominant visibility term on a mountain — far more than the haze
    /// or fog a valley station reports — so falling snow overrides the station reading.
    static func visibility(
        _ observation: StationObservation,
        snowfallCmPerHour: Double
    ) -> Double {
        guard snowfallCmPerHour > 0.1 else {
            return observation.visibilityM
        }
        // 0.5 cm/h ≈ light flurries, still ~2 km. 4 cm/h ≈ true whiteout, under 100 m.
        let snowLimited = 4_000 * exp(-snowfallCmPerHour * 0.95)
        return max(50, min(observation.visibilityM, snowLimited))
    }
}
