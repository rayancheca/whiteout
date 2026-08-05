import Foundation

/// A weather reading at the player's real location, at their real local time.
///
/// This is deliberately a plain value type with no provider vocabulary in it — the
/// Open-Meteo decoder maps into this, and any future provider maps into the same shape.
/// Everything downstream (translation, snow state, physics, palette) depends only on this.
public struct StationObservation: Sendable, Equatable {

    // MARK: Instantaneous

    public let temperatureC: Double
    public let relativeHumidityPercent: Double
    /// Liquid-equivalent precipitation rate.
    public let precipitationMmPerHour: Double
    public let windSpeedKmh: Double
    public let windGustKmh: Double
    /// Meteorological convention: the direction the wind is coming *from*, clockwise from north.
    public let windDirectionDeg: Double
    public let cloudCoverPercent: Double
    public let visibilityM: Double
    /// Height of the 0 °C isotherm above sea level. The single most useful field for
    /// deciding whether precipitation at altitude falls as snow.
    public let freezingLevelM: Double

    // MARK: Trailing 24 hours
    //
    // History is not decoration: a freeze–thaw cycle is invisible in an instantaneous
    // reading, yet it is the difference between forgiving corn snow and lethal crust.

    public let maxTemperature24hC: Double
    public let minTemperature24hC: Double
    public let precipitation24hMm: Double

    // MARK: Site & solar

    /// Ground elevation of the observation point, above sea level.
    public let elevationM: Double
    /// Sun angle above the horizon. Negative at night; drives the entire palette.
    public let sunAltitudeDeg: Double
    /// The player's wall-clock hour, used for time-of-day framing.
    public let localHour: Double

    public init(
        temperatureC: Double,
        relativeHumidityPercent: Double,
        precipitationMmPerHour: Double,
        windSpeedKmh: Double,
        windGustKmh: Double,
        windDirectionDeg: Double,
        cloudCoverPercent: Double,
        visibilityM: Double,
        freezingLevelM: Double,
        maxTemperature24hC: Double,
        minTemperature24hC: Double,
        precipitation24hMm: Double,
        elevationM: Double,
        sunAltitudeDeg: Double,
        localHour: Double
    ) {
        self.temperatureC = temperatureC
        self.relativeHumidityPercent = relativeHumidityPercent
        self.precipitationMmPerHour = precipitationMmPerHour
        self.windSpeedKmh = windSpeedKmh
        self.windGustKmh = windGustKmh
        self.windDirectionDeg = windDirectionDeg
        self.cloudCoverPercent = cloudCoverPercent
        self.visibilityM = visibilityM
        self.freezingLevelM = freezingLevelM
        self.maxTemperature24hC = maxTemperature24hC
        self.minTemperature24hC = minTemperature24hC
        self.precipitation24hMm = precipitation24hMm
        self.elevationM = elevationM
        self.sunAltitudeDeg = sunAltitudeDeg
        self.localHour = localHour
    }
}
