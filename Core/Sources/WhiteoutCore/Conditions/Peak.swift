import Foundation

/// An elevation the player can ski from.
///
/// Elevation is the game's progression axis, and it exists because two measurements forced
/// it. At a fixed 2,800 m a tropical player gets spring slush every single day, and *every*
/// player gets packed or slush through the northern summer — so the snow-state model, which
/// the whole design rests on, would spend half the year unable to reach four of its six
/// states. Raising the mountain restores the full range from the same real weather.
///
/// Peaks are unlocked by distance skied and can never be purchased. That is deliberate:
/// altitude changes speed and difficulty, so selling it would be selling power. Cosmetics
/// and archived storms are sideways content; this is not, so it stays free.
public struct Peak: Sendable, Equatable, Identifiable, Codable {

    public let id: String
    public let name: String
    public let elevationM: Double
    /// Lifetime distance in metres required before this peak becomes available.
    public let unlockDistanceM: Double

    public init(id: String, name: String, elevationM: Double, unlockDistanceM: Double) {
        self.id = id
        self.name = name
        self.elevationM = elevationM
        self.unlockDistanceM = unlockDistanceM
    }

    public static let resort = Peak(
        id: "resort", name: "The Resort",
        elevationM: 2_800, unlockDistanceM: 0
    )

    public static let spine = Peak(
        id: "spine", name: "The Spine",
        elevationM: 3_600, unlockDistanceM: 25_000
    )

    public static let col = Peak(
        id: "col", name: "The Col",
        elevationM: 4_400, unlockDistanceM: 100_000
    )

    public static let thinAir = Peak(
        id: "thin-air", name: "Thin Air",
        elevationM: 5_200, unlockDistanceM: 300_000
    )

    /// Ordered low to high.
    public static let all: [Peak] = [.resort, .spine, .col, .thinAir]

    public static func unlocked(forLifetimeDistanceM distance: Double) -> [Peak] {
        all.filter { distance >= $0.unlockDistanceM }
    }

    /// The next peak to work toward, or `nil` when everything is unlocked.
    public static func next(afterLifetimeDistanceM distance: Double) -> Peak? {
        all.first { distance < $0.unlockDistanceM }
    }
}

public extension MountainWeather {

    /// Air density here, relative to the base resort elevation.
    ///
    /// Barometric approximation `exp(-h/H)` with a scale height of 8,500 m. Computed rather
    /// than stored so elevation remains the single source of truth — there is no way for a
    /// density field to drift out of agreement with the altitude it came from.
    var airDensityRatio: Double {
        let scaleHeightM = 8_500.0
        return exp(-elevationM / scaleHeightM)
            / exp(-AltitudeTranslation.mountainElevationM / scaleHeightM)
    }
}

public extension SnowPhysics {

    /// Adapts a snowpack profile to thin air.
    ///
    /// Aerodynamic drag scales directly with air density, so a high peak is measurably
    /// faster on identical snow — roughly 25% less drag at 5,200 m. This is the reward for
    /// climbing, and the punishment: the same crust that was survivable at the resort
    /// arrives noticeably quicker up high. Grip and float are untouched, because they are
    /// properties of the snow, not of the atmosphere.
    func atAltitude(densityRatio: Double) -> SnowPhysics {
        let clamped = min(max(densityRatio, 0.4), 1.2)
        return SnowPhysics(
            grip: grip,
            float: float,
            drag: drag * clamped,
            // Top speed rises as the square root of falling density, since drag balances
            // thrust at v² — a linear scaling here would badly overstate the gain.
            topSpeedMultiplier: topSpeedMultiplier / sqrt(clamped),
            chatter: chatter,
            sprayDensity: sprayDensity,
            carveePenaltyExponent: carveePenaltyExponent
        )
    }
}
