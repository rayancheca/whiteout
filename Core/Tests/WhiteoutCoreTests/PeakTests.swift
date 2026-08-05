import Testing
import Foundation
@testable import WhiteoutCore

/// A mid-summer northern observation — the case that exposed the diversity problem.
private func summerStation(
    temperatureC: Double,
    elevationM: Double = 30,
    precipitation24hMm: Double = 0,
    precipitationMmPerHour: Double = 0
) -> StationObservation {
    StationObservation(
        temperatureC: temperatureC,
        relativeHumidityPercent: 72,
        precipitationMmPerHour: precipitationMmPerHour,
        // Deliberately calm. Exposure more than doubles wind at altitude, so a merely
        // breezy town becomes a scoured ridge — enough to classify as ice on its own and
        // mask whatever the test was actually trying to measure.
        windSpeedKmh: 8,
        windGustKmh: 12,
        windDirectionDeg: 250,
        cloudCoverPercent: 55,
        visibilityM: 30_000,
        freezingLevelM: 3_400,
        maxTemperature24hC: temperatureC + 3,
        minTemperature24hC: temperatureC - 4,
        precipitation24hMm: precipitation24hMm,
        elevationM: elevationM,
        sunAltitudeDeg: 38,
        localHour: 13
    )
}

@Suite("Peaks and altitude")
struct PeakTests {

    @Test("peaks unlock in order as distance accumulates")
    func unlocksByDistance() {
        #expect(Peak.unlocked(forLifetimeDistanceM: 0).map(\.id) == ["resort"])
        #expect(Peak.unlocked(forLifetimeDistanceM: 30_000).map(\.id) == ["resort", "spine"])
        #expect(Peak.unlocked(forLifetimeDistanceM: 500_000).count == Peak.all.count)
    }

    @Test("the next target is reported until everything is unlocked")
    func reportsNextGoal() {
        #expect(Peak.next(afterLifetimeDistanceM: 0)?.id == "spine")
        #expect(Peak.next(afterLifetimeDistanceM: 120_000)?.id == "thin-air")
        #expect(Peak.next(afterLifetimeDistanceM: 999_999) == nil)
    }

    @Test("peaks are ordered by elevation and never purchasable")
    func laddersUpward() {
        let elevations = Peak.all.map(\.elevationM)
        #expect(elevations == elevations.sorted())
        // Unlock cost is expressed only in distance. There is no price field, by design:
        // altitude changes speed, so selling it would be selling power.
        #expect(Peak.all.allSatisfy { $0.unlockDistanceM >= 0 })
    }

    @Test("air thins with altitude")
    func airDensityFalls() {
        let observation = summerStation(temperatureC: 12)
        let resort = AltitudeTranslation.lift(observation, to: Peak.resort.elevationM)
        let high = AltitudeTranslation.lift(observation, to: Peak.thinAir.elevationM)

        // Ratios are expressed relative to the resort, so the base peak is exactly 1.
        #expect(abs(resort.airDensityRatio - 1) < 0.0001)
        #expect(high.airDensityRatio < 0.8)
        #expect(high.airDensityRatio > 0.6)
    }

    @Test("thin air reduces drag and raises top speed")
    func altitudeIsFasterAndLooser() {
        let base = SnowPhysics.profile(for: .packed)
        let high = base.atAltitude(densityRatio: 0.75)

        #expect(high.drag < base.drag)
        #expect(high.topSpeedMultiplier > base.topSpeedMultiplier)
        // Grip and float belong to the snow, not the atmosphere, and must not drift.
        #expect(high.grip == base.grip)
        #expect(high.float == base.float)
    }

    @Test("the base peak leaves physics exactly unchanged")
    func resortIsIdentity() {
        for state in SnowState.allCases {
            let base = SnowPhysics.profile(for: state)
            #expect(base.atAltitude(densityRatio: 1.0) == base)
        }
    }

    @Test("altitude restores snow-state variety in midsummer")
    func altitudeFixesSummerMonotony() {
        // Measured from the running build: Reykjavík in early August translated to plain
        // packed snow at the resort, as did Cupertino. Four of the six snow states were
        // simply unreachable for half the year at a single fixed elevation.
        let august = summerStation(temperatureC: 12)

        let atResort = SnowState.classify(AltitudeTranslation.lift(august, to: Peak.resort.elevationM))
        let atThinAir = SnowState.classify(AltitudeTranslation.lift(august, to: Peak.thinAir.elevationM))

        #expect(atResort == .packed)
        // 2,400 m higher is ~15 °C colder, which reaches states the resort cannot in summer.
        #expect(atThinAir != atResort)
    }

    @Test("a summer storm becomes a powder day higher up")
    func altitudeConvertsRainToPowder() {
        // 24 °C in town. Warm enough that the resort is genuinely above freezing — at 14 °C
        // the lapse rate alone already puts 2,800 m below zero, so there would be no rain
        // anywhere and the test would prove nothing.
        let wetSummerDay = summerStation(
            temperatureC: 24,
            precipitation24hMm: 22,
            precipitationMmPerHour: 2
        )

        let resort = AltitudeTranslation.lift(wetSummerDay, to: Peak.resort.elevationM)
        let high = AltitudeTranslation.lift(wetSummerDay, to: Peak.col.elevationM)

        // Rain on a warm mountain; genuine snowfall on a cold one, from one real forecast.
        #expect(resort.isRainingAtAltitude)
        #expect(!high.isRainingAtAltitude)
        #expect(high.freshSnowCm > 15)
        #expect(SnowState.classify(high) == .powder || SnowState.classify(high) == .windSlab)
    }

    @Test("each peak is a genuinely different mountain")
    func peakChangesTerrainSeed() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let observation = summerStation(temperatureC: 10)

        let low = RunConditions.resolve(
            from: observation, placeName: "Test", bucketKey: "abcd", peak: .resort, at: now
        )
        let high = RunConditions.resolve(
            from: observation, placeName: "Test", bucketKey: "abcd", peak: .col, at: now
        )

        #expect(low.seed != high.seed)
        #expect(low.weather.temperatureC > high.weather.temperatureC)
    }

    @Test("resolved conditions carry altitude-adjusted physics")
    func resolveAppliesAltitude() {
        let observation = summerStation(temperatureC: 6)
        let high = RunConditions.resolve(
            from: observation, placeName: "Test", bucketKey: "abcd", peak: .thinAir
        )
        let unadjusted = SnowPhysics.profile(for: high.snowState)
        #expect(high.physics.topSpeedMultiplier > unadjusted.topSpeedMultiplier)
    }
}
