import Foundation

/// Where the sun is, for a place and a moment.
///
/// The palette is driven almost entirely by solar altitude, and no weather API reports it,
/// so it is computed locally. That is the better arrangement anyway: it costs nothing, works
/// offline, and stays correct while cached weather goes stale — a run at 17:00 gets a real
/// sunset even if the conditions packet was fetched at noon.
///
/// Implements the NOAA low-precision solar position algorithm, accurate to well under a
/// degree, which is far finer than the palette can express.
public enum SolarPosition {

    /// Sun altitude above the horizon in degrees. Negative below the horizon.
    public static func altitudeDegrees(
        latitude: Double,
        longitude: Double,
        date: Date,
        timeZoneOffsetHours: Double
    ) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt

        let components = calendar.dateComponents([.dayOfYear, .hour, .minute, .second], from: date)
        let dayOfYear = Double(components.dayOfYear ?? 1)
        let utcMinutes = Double(components.hour ?? 0) * 60
            + Double(components.minute ?? 0)
            + Double(components.second ?? 0) / 60

        // Fractional year, radians.
        let gamma = 2 * .pi / 365 * (dayOfYear - 1 + (utcMinutes / 60 - 12) / 24)

        let declination = 0.006918
            - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.001480 * sin(3 * gamma)

        let equationOfTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma)
        )

        // Convert to true solar time at this longitude.
        let localMinutes = utcMinutes + timeZoneOffsetHours * 60
        let offset = equationOfTime + 4 * longitude - 60 * timeZoneOffsetHours
        let trueSolarMinutes = localMinutes.truncatingRemainder(dividingBy: 1_440) + offset

        // Hour angle: zero at solar noon, ±180° at solar midnight.
        let hourAngle = (trueSolarMinutes / 4 - 180) * .pi / 180

        let latitudeRadians = latitude * .pi / 180
        let cosZenith = sin(latitudeRadians) * sin(declination)
            + cos(latitudeRadians) * cos(declination) * cos(hourAngle)

        let zenith = acos(min(max(cosZenith, -1), 1))
        return 90 - zenith * 180 / .pi
    }
}
