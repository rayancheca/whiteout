import Foundation
import CoreLocation
import Observation
import WhiteoutCore

/// A place the player can ski from. Either their real location, or a fixed city.
struct Origin: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D?

    static let here = Origin(id: "here", name: "My Location", coordinate: nil)

    /// Reference cities spanning the climate range the translation model has to survive.
    ///
    /// Kept in the shipping build behind a dev affordance because they are the fastest way
    /// to check that the model behaves across the whole world rather than just wherever
    /// the developer happens to be standing.
    static let showcase: [Origin] = [
        .here,
        Origin(id: "chamonix", name: "Chamonix", coordinate: .init(latitude: 45.9237, longitude: 6.8694)),
        Origin(id: "reykjavik", name: "Reykjavík", coordinate: .init(latitude: 64.1466, longitude: -21.9426)),
        Origin(id: "tokyo", name: "Tokyo", coordinate: .init(latitude: 35.6762, longitude: 139.6503)),
        Origin(id: "miami", name: "Miami", coordinate: .init(latitude: 25.7617, longitude: -80.1918)),
        Origin(id: "dubai", name: "Dubai", coordinate: .init(latitude: 25.2048, longitude: 55.2708))
    ]

    static func == (lhs: Origin, rhs: Origin) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Resolves the conditions for a run and holds them for the session.
///
/// Deliberately never surfaces a failure state to the player. Location denied, network
/// down, provider erroring — all of them land on playable fallback conditions instead of
/// an error screen, because a weather-driven game that refuses to start without weather
/// has confused its input for its product.
@Observable
@MainActor
final class ConditionsStore {

    private(set) var conditions: RunConditions = .fallback()
    private(set) var isLoading = false
    /// Surfaced quietly in the UI, never as a blocking alert.
    private(set) var usingFallback = true

    var origin: Origin = .here
    var peak: Peak = .resort

    /// Total distance skied across all sessions — the only thing that unlocks peaks.
    /// Persisted so progression survives a relaunch.
    private(set) var lifetimeDistanceM: Double = UserDefaults.standard.double(forKey: "lifetimeDistanceM")

    var unlockedPeaks: [Peak] { Peak.unlocked(forLifetimeDistanceM: lifetimeDistanceM) }

    func recordRun(distanceM: Double) {
        lifetimeDistanceM += distanceM
        UserDefaults.standard.set(lifetimeDistanceM, forKey: "lifetimeDistanceM")
    }

    private let provider: WeatherProvider
    private let locator = LocationProvider()

    init(provider: WeatherProvider = OpenMeteoClient()) {
        self.provider = provider
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let coordinate = await resolveCoordinate() else {
            usingFallback = true
            conditions = .fallback()
            return
        }

        let bucket = LocationBucket(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let observation = try await provider.observation(for: bucket)
            conditions = RunConditions.resolve(
                from: observation,
                placeName: origin.id == Origin.here.id ? "Your Mountain" : origin.name,
                bucketKey: bucket.geohash,
                peak: peak
            )
            usingFallback = false
        } catch {
            // Intentionally silent to the player. The run still happens.
            usingFallback = true
            conditions = .fallback()
        }
    }

    private func resolveCoordinate() async -> CLLocationCoordinate2D? {
        if let fixed = origin.coordinate { return fixed }
        return await locator.currentCoordinate()
    }
}

/// Thin CoreLocation wrapper with a hard timeout.
///
/// The timeout is the point. CoreLocation can hang indefinitely when permission is
/// undetermined or no fix is available — common on a simulator — and a menu that waits on
/// it appears frozen. Four seconds, then we move on with defaults.
private final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentCoordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}
