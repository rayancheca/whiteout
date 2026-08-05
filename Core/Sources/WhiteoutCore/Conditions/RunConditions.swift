import Foundation

/// Everything one run needs, resolved once before play starts.
///
/// This is the architectural keystone. It is assembled from the network *before* the run
/// begins and is then treated as immutable, so gameplay makes zero network calls and runs
/// identically in airplane mode. It is also the reason the concept is buildable at all:
/// of the five candidate designs, this was the only one where every third-party dependency
/// could be resolved off the frame-time critical path and cached.
///
/// Because `seed` fully determines terrain, replays and ghosts are input tapes rather than
/// recorded positions, and a score can be verified server-side by re-simulation.
public struct RunConditions: Sendable, Equatable {

    /// Determines terrain, prop placement and weather events. The whole run is a pure
    /// function of this value plus player input.
    public let seed: UInt64

    /// Where the player physically is, rounded for privacy (see `LocationBucket`).
    public let placeName: String

    public let weather: MountainWeather
    public let snowState: SnowState
    public let physics: SnowPhysics
    public let palette: ScenePalette

    /// When this was resolved. Drives the stale-while-revalidate refresh policy.
    public let resolvedAt: Date

    public init(
        seed: UInt64,
        placeName: String,
        weather: MountainWeather,
        snowState: SnowState,
        physics: SnowPhysics,
        palette: ScenePalette,
        resolvedAt: Date
    ) {
        self.seed = seed
        self.placeName = placeName
        self.weather = weather
        self.snowState = snowState
        self.physics = physics
        self.palette = palette
        self.resolvedAt = resolvedAt
    }

    /// Builds a full condition set from a raw observation.
    ///
    /// The seed deliberately quantises time to the hour and temperature to whole degrees.
    /// Two players in the same city in the same hour therefore ski *the same mountain* and
    /// can compare honestly, while the next hour brings genuinely new terrain.
    public static func resolve(
        from observation: StationObservation,
        placeName: String,
        bucketKey: String,
        peak: Peak = .resort,
        at date: Date = Date()
    ) -> RunConditions {
        let weather = AltitudeTranslation.lift(observation, to: peak.elevationM)
        let state = SnowState.classify(weather)

        // The peak is part of the seed so each elevation is a genuinely different mountain
        // rather than the same contours viewed in colder air.
        let hourKey = Int(date.timeIntervalSince1970 / 3_600)
        let seedSource = "\(bucketKey)|\(hourKey)|\(peak.id)|\(state.rawValue)|\(Int(weather.temperatureC.rounded()))"

        return RunConditions(
            seed: SeededRandom(key: seedSource).seed,
            placeName: placeName,
            weather: weather,
            snowState: state,
            physics: SnowPhysics.profile(for: state)
                .atAltitude(densityRatio: weather.airDensityRatio),
            palette: PaletteGenerator.palette(for: weather, state: state),
            resolvedAt: date
        )
    }

    /// Conditions used when location is denied or the network is unreachable.
    ///
    /// A cold, clear, calm morning: the state that best teaches the controls. Never a
    /// blocking error — a weather game that refuses to start without weather has confused
    /// its input for its product.
    public static func fallback(at date: Date = Date()) -> RunConditions {
        let weather = MountainWeather(
            elevationM: AltitudeTranslation.mountainElevationM,
            temperatureC: -7,
            freshSnowCm: 12,
            snowfallCmPerHour: 0,
            isRainingAtAltitude: false,
            windSpeedKmh: 9,
            windGustKmh: 14,
            windDirectionDeg: 315,
            visibilityM: 4_000,
            cloudCoverPercent: 18,
            sunAltitudeDeg: 22,
            localHour: 9,
            maxTemperature24hC: -4,
            minTemperature24hC: -12
        )
        let state = SnowState.classify(weather)
        return RunConditions(
            seed: SeededRandom(key: "whiteout.fallback").seed,
            placeName: "Unknown Range",
            weather: weather,
            snowState: state,
            physics: SnowPhysics.profile(for: state),
            palette: PaletteGenerator.palette(for: weather, state: state),
            resolvedAt: date
        )
    }

    /// Whether these conditions should be refreshed.
    ///
    /// Fifteen minutes because weather genuinely moves on ten-minute scales; anything
    /// tighter spends battery and quota to deliver a difference no player can perceive.
    public var isStale: Bool {
        Date().timeIntervalSince(resolvedAt) > 900
    }

    /// Header line for the conditions card, in ski-report register.
    public var headline: String {
        let temperature = Int(weather.temperatureC.rounded())
        if weather.snowfallCmPerHour > 0.1 {
            return "\(placeName) · \(temperature)°C · snowing"
        }
        if weather.freshSnowCm >= 5 {
            return "\(placeName) · \(temperature)°C · \(Int(weather.freshSnowCm))cm new"
        }
        return "\(placeName) · \(temperature)°C · \(snowState.displayName.lowercased())"
    }
}

/// Coarsens a coordinate before it ever leaves the device.
///
/// Precision-4 geohash cells are roughly 20 km across, which serves two goals with one
/// decision: a cache key shared by everyone in a metro area (very high hit rate, so the
/// weather API is called once for thousands of players), and the guarantee that no precise
/// user location is transmitted or stored anywhere. The privacy win and the latency win
/// are the same mechanism.
public struct LocationBucket: Sendable, Equatable {

    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    public let geohash: String
    /// Cell-centre latitude — what is actually sent to the weather provider.
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double, precision: Int = 4) {
        self.geohash = Self.encode(latitude: latitude, longitude: longitude, precision: precision)
        let centre = Self.decodeCentre(self.geohash)
        self.latitude = centre.latitude
        self.longitude = centre.longitude
    }

    static func encode(latitude: Double, longitude: Double, precision: Int) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bit = 0
        var characterIndex = 0
        var isLongitudeTurn = true

        while hash.count < precision {
            if isLongitudeTurn {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    characterIndex = characterIndex << 1 | 1
                    lonRange.0 = mid
                } else {
                    characterIndex = characterIndex << 1
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    characterIndex = characterIndex << 1 | 1
                    latRange.0 = mid
                } else {
                    characterIndex = characterIndex << 1
                    latRange.1 = mid
                }
            }
            isLongitudeTurn.toggle()
            bit += 1

            if bit == 5 {
                hash.append(base32[characterIndex])
                bit = 0
                characterIndex = 0
            }
        }
        return hash
    }

    static func decodeCentre(_ geohash: String) -> (latitude: Double, longitude: Double) {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isLongitudeTurn = true

        for character in geohash {
            guard let value = base32.firstIndex(of: character) else { continue }
            for shift in stride(from: 4, through: 0, by: -1) {
                let bit = (value >> shift) & 1
                if isLongitudeTurn {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if bit == 1 { lonRange.0 = mid } else { lonRange.1 = mid }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if bit == 1 { latRange.0 = mid } else { latRange.1 = mid }
                }
                isLongitudeTurn.toggle()
            }
        }

        return ((latRange.0 + latRange.1) / 2, (lonRange.0 + lonRange.1) / 2)
    }
}
