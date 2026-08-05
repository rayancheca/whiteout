import Foundation

/// Anything that can supply a weather observation. Lets tests and previews run without a network.
public protocol WeatherProvider: Sendable {
    func observation(for bucket: LocationBucket) async throws -> StationObservation
}

public enum WeatherProviderError: Error, Sendable {
    case badResponse(status: Int)
    case malformedPayload
}

/// Open-Meteo client.
///
/// Chosen over OpenWeather for a decisive reason: it reports `freezing_level_height`,
/// `snowfall`, `snow_depth` and `visibility` on the free tier. OpenWeather reports none of
/// the snowpack fields, so it literally cannot drive the snow-state model — the concept's
/// original API choice would have forced the weather back into being a cosmetic filter.
/// It also needs no API key, which removes a secret from the client binary entirely.
public struct OpenMeteoClient: WeatherProvider {

    private let session: URLSession
    private let host = "api.open-meteo.com"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func observation(for bucket: LocationBucket) async throws -> StationObservation {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1/forecast"
        components.queryItems = [
            // Cell centre, never the device's precise position.
            .init(name: "latitude", value: String(format: "%.3f", bucket.latitude)),
            .init(name: "longitude", value: String(format: "%.3f", bucket.longitude)),
            .init(name: "current", value: [
                "temperature_2m", "relative_humidity_2m", "precipitation",
                "cloud_cover", "wind_speed_10m", "wind_gusts_10m", "wind_direction_10m"
            ].joined(separator: ",")),
            .init(name: "hourly", value: "visibility,freezing_level_height"),
            // past_days is what makes freeze–thaw detection possible; without yesterday's
            // range the model cannot tell fresh powder from refrozen crust.
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_sum"),
            .init(name: "past_days", value: "1"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { throw WeatherProviderError.malformedPayload }

        var request = URLRequest(url: url)
        // Tight timeout: a slow weather call must never hold up the menu. The caller falls
        // back to cached or default conditions rather than waiting.
        request.timeoutInterval = 6

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WeatherProviderError.malformedPayload
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherProviderError.badResponse(status: http.statusCode)
        }

        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return payload.toObservation()
    }
}

// MARK: - Wire format

/// Mirrors Open-Meteo's JSON exactly, and is not used anywhere else.
///
/// Keeping the provider's shape quarantined in this file is what allows a second provider
/// to be added later without any change to the model, the physics, or the renderer.
struct OpenMeteoResponse: Decodable {

    struct Current: Decodable {
        let temperature_2m: Double?
        let relative_humidity_2m: Double?
        let precipitation: Double?
        let cloud_cover: Double?
        let wind_speed_10m: Double?
        let wind_gusts_10m: Double?
        let wind_direction_10m: Double?
    }

    struct Hourly: Decodable {
        let time: [String]?
        let visibility: [Double?]?
        let freezing_level_height: [Double?]?
    }

    struct Daily: Decodable {
        let temperature_2m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let precipitation_sum: [Double?]?
    }

    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let utc_offset_seconds: Int?
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?

    func toObservation(now: Date = Date()) -> StationObservation {
        let offsetHours = Double(utc_offset_seconds ?? 0) / 3_600
        let localHour = localHour(now: now, offsetHours: offsetHours)

        // Hourly arrays span yesterday and today because of `past_days=1`; index by
        // position from the start rather than trusting a fixed offset.
        let hourIndex = currentHourIndex(now: now, offsetHours: offsetHours)
        let visibility = hourly?.visibility?[safe: hourIndex].flatMap { $0 } ?? 10_000
        let freezingLevel = hourly?.freezing_level_height?[safe: hourIndex].flatMap { $0 } ?? 2_000

        // Daily arrays are [yesterday, today]. The 24 h window that matters spans both, so
        // take the extremes across the pair — a thaw at 15:00 yesterday still governs the
        // snowpack this morning.
        let maxima = (daily?.temperature_2m_max ?? []).compactMap { $0 }
        let minima = (daily?.temperature_2m_min ?? []).compactMap { $0 }
        let precipitationTotals = (daily?.precipitation_sum ?? []).compactMap { $0 }

        let elevationM = elevation ?? 0

        return StationObservation(
            temperatureC: current?.temperature_2m ?? 0,
            relativeHumidityPercent: current?.relative_humidity_2m ?? 60,
            precipitationMmPerHour: current?.precipitation ?? 0,
            windSpeedKmh: current?.wind_speed_10m ?? 0,
            windGustKmh: current?.wind_gusts_10m ?? (current?.wind_speed_10m ?? 0) * 1.4,
            windDirectionDeg: current?.wind_direction_10m ?? 0,
            cloudCoverPercent: current?.cloud_cover ?? 0,
            visibilityM: visibility,
            freezingLevelM: freezingLevel,
            maxTemperature24hC: maxima.max() ?? (current?.temperature_2m ?? 0),
            minTemperature24hC: minima.min() ?? (current?.temperature_2m ?? 0),
            precipitation24hMm: precipitationTotals.reduce(0, +),
            elevationM: elevationM,
            sunAltitudeDeg: SolarPosition.altitudeDegrees(
                latitude: latitude,
                longitude: longitude,
                date: now,
                timeZoneOffsetHours: offsetHours
            ),
            localHour: localHour
        )
    }

    private func localHour(now: Date, offsetHours: Double) -> Double {
        let secondsIntoUTCDay = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)
        let local = (secondsIntoUTCDay / 3_600 + offsetHours).truncatingRemainder(dividingBy: 24)
        return local < 0 ? local + 24 : local
    }

    /// Index of the current hour within the hourly arrays, which begin at midnight yesterday.
    private func currentHourIndex(now: Date, offsetHours: Double) -> Int {
        24 + Int(localHour(now: now, offsetHours: offsetHours))
    }
}

extension Array {
    /// Bounds-checked subscript. Provider arrays vary in length by query and location, so
    /// indexing them defensively keeps a short array from crashing the app on launch.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
