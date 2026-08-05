import Testing
import Foundation
@testable import WhiteoutCore

// MARK: - Fixtures

/// A neutral mid-winter mountain day, overridable per test.
private func mountain(
    temperatureC: Double = -5,
    freshSnowCm: Double = 3,
    snowfallCmPerHour: Double = 0,
    isRaining: Bool = false,
    windGustKmh: Double = 12,
    visibilityM: Double = 4_000,
    cloudCoverPercent: Double = 30,
    sunAltitudeDeg: Double = 25,
    maxTemperature24hC: Double = -3,
    minTemperature24hC: Double = -9
) -> MountainWeather {
    MountainWeather(
        elevationM: 2_800,
        temperatureC: temperatureC,
        freshSnowCm: freshSnowCm,
        snowfallCmPerHour: snowfallCmPerHour,
        isRainingAtAltitude: isRaining,
        windSpeedKmh: windGustKmh * 0.7,
        windGustKmh: windGustKmh,
        windDirectionDeg: 300,
        visibilityM: visibilityM,
        cloudCoverPercent: cloudCoverPercent,
        sunAltitudeDeg: sunAltitudeDeg,
        localHour: 10,
        maxTemperature24hC: maxTemperature24hC,
        minTemperature24hC: minTemperature24hC
    )
}

/// A city observation, defaulting to a temperate winter town near sea level.
private func station(
    temperatureC: Double = 2,
    precipitationMmPerHour: Double = 0,
    precipitation24hMm: Double = 0,
    windSpeedKmh: Double = 15,
    elevationM: Double = 50,
    freezingLevelM: Double = 1_200,
    maxTemperature24hC: Double = 4,
    minTemperature24hC: Double = -1,
    visibilityM: Double = 12_000
) -> StationObservation {
    StationObservation(
        temperatureC: temperatureC,
        relativeHumidityPercent: 70,
        precipitationMmPerHour: precipitationMmPerHour,
        windSpeedKmh: windSpeedKmh,
        windGustKmh: windSpeedKmh * 1.5,
        windDirectionDeg: 270,
        cloudCoverPercent: 60,
        visibilityM: visibilityM,
        freezingLevelM: freezingLevelM,
        maxTemperature24hC: maxTemperature24hC,
        minTemperature24hC: minTemperature24hC,
        precipitation24hMm: precipitation24hMm,
        elevationM: elevationM,
        sunAltitudeDeg: 20,
        localHour: 11
    )
}

// MARK: - Determinism

@Suite("Seeded randomness")
struct SeededRandomTests {

    @Test("the same seed and index always produce the same value")
    func isReproducible() {
        let a = SeededRandom(seed: 12_345)
        let b = SeededRandom(seed: 12_345)
        for index in UInt64(0)..<50 {
            #expect(a.raw(at: index) == b.raw(at: index))
        }
    }

    @Test("values can be sampled out of order — no hidden cursor")
    func isIndexedNotSequential() {
        let generator = SeededRandom(seed: 99)
        let farValueFirst = SeededRandom(seed: 99).raw(at: 100_000)
        _ = generator.raw(at: 0)
        _ = generator.raw(at: 1)
        // Reading earlier indices must not change what index 100_000 returns; this is the
        // property that lets a server verify a score by re-simulating from the seed alone.
        #expect(generator.raw(at: 100_000) == farValueFirst)
    }

    @Test("different seeds diverge")
    func differentSeedsDiffer() {
        #expect(SeededRandom(seed: 1).raw(at: 0) != SeededRandom(seed: 2).raw(at: 0))
    }

    @Test("named domains are independent streams")
    func domainsAreIsolated() {
        let root = SeededRandom(seed: 7)
        #expect(root.domain("terrain").seed != root.domain("props").seed)
        // Stable across calls, so adding a subsystem never reshuffles an existing one.
        #expect(root.domain("terrain").seed == root.domain("terrain").seed)
    }

    @Test("unit values stay in range")
    func unitIsBounded() {
        let generator = SeededRandom(seed: 4_242)
        for index in UInt64(0)..<1_000 {
            let value = generator.unit(at: index)
            #expect(value >= 0 && value < 1)
        }
    }

    @Test("fbm output stays bounded")
    func fbmIsBounded() {
        let generator = SeededRandom(seed: 8)
        for step in 0..<500 {
            let value = generator.fbm(at: Double(step) * 0.37, octaves: 4, frequency: 0.05)
            #expect(value >= -1.01 && value <= 1.01)
        }
    }
}

// MARK: - Altitude translation

@Suite("Altitude translation")
struct AltitudeTranslationTests {

    @Test("temperature falls at the environmental lapse rate")
    func appliesLapseRate() {
        let observed = station(temperatureC: 10, elevationM: 0)
        let lifted = AltitudeTranslation.lift(observed, to: 2_000)
        // 2 km × 6.5 °C/km = 13 °C of cooling.
        #expect(abs(lifted.temperatureC - (-3)) < 0.01)
    }

    @Test("rain in the city becomes snowfall on the mountain")
    func convertsRainToSnow() {
        // 5 °C and raining at sea level — no snow anywhere the player can see.
        let observed = station(
            temperatureC: 5,
            precipitationMmPerHour: 2,
            precipitation24hMm: 30,
            freezingLevelM: 900
        )
        let lifted = AltitudeTranslation.lift(observed)

        #expect(lifted.temperatureC < 0)
        #expect(!lifted.isRainingAtAltitude)
        #expect(lifted.snowfallCmPerHour > 0)
        // 30 mm liquid at roughly −13 °C → a substantial storm total.
        #expect(lifted.freshSnowCm > 30)
    }

    @Test("colder air makes deeper snow from identical precipitation")
    func snowRatioScalesWithCold() {
        let mild = AltitudeTranslation.lift(station(temperatureC: 8, precipitation24hMm: 20))
        let frigid = AltitudeTranslation.lift(station(temperatureC: -8, precipitation24hMm: 20))
        // Same water content, more depth when cold — the reason a cold city translates to
        // a better mountain day than a merely wet one.
        #expect(frigid.freshSnowCm > mild.freshSnowCm)
    }

    @Test("a tropical city still yields a valid mountain day")
    func tropicalCityIsPlayable() {
        // Lagos in the dry season: the case that would exclude a huge share of players
        // if the game simply rendered local weather.
        let lagos = station(temperatureC: 32, elevationM: 40, freezingLevelM: 4_800)
        let lifted = AltitudeTranslation.lift(lagos)

        #expect(lifted.temperatureC < 16)
        // Warm, so it classifies as spring slush — a real alpine surface, not an error state.
        #expect(SnowState.classify(lifted) == .slush)
    }

    @Test("elevation is the lever that gives hot climates true winter")
    func higherElevationUnlocksSnow() {
        let miami = station(
            temperatureC: 30,
            precipitationMmPerHour: 3,
            precipitation24hMm: 25,
            elevationM: 2,
            freezingLevelM: 4_700
        )
        let standard = AltitudeTranslation.lift(miami, to: 2_800)
        let extreme = AltitudeTranslation.lift(miami, to: 5_200)

        // At resort height a tropical player gets slush every time — monotonous.
        #expect(standard.temperatureC > 0)
        // At Andean height the same real weather becomes genuine snowfall. This documents
        // elevation as a progression axis rather than a fixed constant.
        #expect(extreme.temperatureC < 0)
        #expect(extreme.snowfallCmPerHour > 0)
    }

    @Test("wind gains with exposure but stays physically bounded")
    func windExposureIsCapped() {
        let gale = station(windSpeedKmh: 90, elevationM: 0)
        let lifted = AltitudeTranslation.lift(gale, to: 2_800)
        #expect(lifted.windSpeedKmh > 90)
        #expect(lifted.windSpeedKmh <= 90 * 2.2 + 0.001)
    }

    @Test("heavy snowfall collapses visibility to a whiteout")
    func snowfallDrivesVisibility() {
        let blizzard = station(
            temperatureC: -6,
            precipitationMmPerHour: 4,
            precipitation24hMm: 40,
            freezingLevelM: 400,
            visibilityM: 20_000
        )
        let lifted = AltitudeTranslation.lift(blizzard)
        // Station reports 20 km; on the mountain, falling snow is the governing term.
        #expect(lifted.visibilityM < 500)
        #expect(lifted.visibilityM >= 50)
    }
}

// MARK: - Snow state classification

@Suite("Snow state classification")
struct SnowStateTests {

    @Test("cold, deep and calm is powder")
    func detectsPowder() {
        let weather = mountain(temperatureC: -8, freshSnowCm: 25, windGustKmh: 10)
        #expect(SnowState.classify(weather) == .powder)
    }

    @Test("a freeze-thaw cycle produces crust even under fresh snow")
    func freezeThawOutranksFreshSnow() {
        // The ordering invariant. Every input here screams "powder day" — 12 cm new, well
        // below freezing — but the pack was above zero in the last 24 h and has refrozen.
        // Any skier would call this survival crust, and a model that checked fresh snow
        // first would confidently report the opposite.
        let weather = mountain(
            temperatureC: -4,
            freshSnowCm: 12,
            maxTemperature24hC: 3
        )
        #expect(SnowState.classify(weather) == .crust)
    }

    @Test("wind turns a powder day into a slab day")
    func windLoadingProducesSlab() {
        let calm = mountain(temperatureC: -8, freshSnowCm: 25, windGustKmh: 10)
        let blown = mountain(temperatureC: -8, freshSnowCm: 25, windGustKmh: 60)
        #expect(SnowState.classify(calm) == .powder)
        #expect(SnowState.classify(blown) == .windSlab)
    }

    @Test("above freezing is always slush, never powder")
    func warmIsNeverPowder() {
        let weather = mountain(temperatureC: 4, freshSnowCm: 30, maxTemperature24hC: 6)
        #expect(SnowState.classify(weather) == .slush)
    }

    @Test("rain at altitude forces slush regardless of temperature reading")
    func rainForcesSlush() {
        let weather = mountain(temperatureC: 0.5, freshSnowCm: 10, isRaining: true, maxTemperature24hC: 0.4)
        #expect(SnowState.classify(weather) == .slush)
    }

    @Test("deep cold with no new snow is boilerplate ice")
    func detectsIce() {
        let weather = mountain(
            temperatureC: -14,
            freshSnowCm: 0,
            windGustKmh: 40,
            maxTemperature24hC: -10,
            minTemperature24hC: -18
        )
        #expect(SnowState.classify(weather) == .ice)
    }

    @Test("an ordinary day settles out as packed")
    func defaultsToPacked() {
        #expect(SnowState.classify(mountain()) == .packed)
    }

    @Test("every state carries player-facing copy")
    func allStatesArePresentable() {
        for state in SnowState.allCases {
            #expect(!state.displayName.isEmpty)
            #expect(!state.reportLine.isEmpty)
        }
    }
}

// MARK: - Physics

@Suite("Snow physics")
struct SnowPhysicsTests {

    @Test("no state is strictly better than another")
    func statesTradeOff() {
        let powder = SnowPhysics.profile(for: .powder)
        let ice = SnowPhysics.profile(for: .ice)

        // Powder is forgiving but slow; ice is lethal but fast. If one dominated the other
        // on every axis, weather would collapse into a difficulty slider.
        #expect(powder.float > ice.float)
        #expect(powder.grip > ice.grip)
        #expect(ice.topSpeedMultiplier > powder.topSpeedMultiplier)
    }

    @Test("all profiles stay within normalised bounds")
    func profilesAreWellFormed() {
        for state in SnowState.allCases {
            let physics = SnowPhysics.profile(for: state)
            #expect(physics.grip > 0 && physics.grip <= 1)
            #expect(physics.float >= 0 && physics.float <= 1)
            #expect(physics.chatter >= 0 && physics.chatter <= 1)
            #expect(physics.topSpeedMultiplier > 0.5 && physics.topSpeedMultiplier < 2)
        }
    }

    @Test("slush punishes hard carving more steeply than packed snow")
    func slushPunishesOverCarving() {
        let packed = SnowPhysics.profile(for: .packed)
        let slush = SnowPhysics.profile(for: .slush)

        // Gentle input: the surfaces feel broadly similar.
        #expect(abs(packed.speedRetention(carveIntensity: 0.2) - slush.speedRetention(carveIntensity: 0.2)) < 0.15)
        // Hard input: slush grabs, which is what makes the correct technique differ.
        #expect(slush.speedRetention(carveIntensity: 1.0) < packed.speedRetention(carveIntensity: 1.0))
    }

    @Test("carving always costs speed, on every surface")
    func carvingIsNeverFree() {
        // Regression. Penalising only over-demand made any carve below the grip limit
        // completely free, so on packed snow tucking and carving produced identical speed
        // and the game's single decision had no consequence. The running build hit top
        // speed while upright, which is what exposed it.
        for state in SnowState.allCases {
            let physics = SnowPhysics.profile(for: state)
            #expect(physics.speedRetention(carveIntensity: 0.5) < 1.0)
            #expect(physics.speedRetention(carveIntensity: 0) == 1.0)
        }
    }

    @Test("ice sheds less speed than firm snow at the same carve")
    func gripDecidesScrubbingPower() {
        let packed = SnowPhysics.profile(for: .packed)
        let ice = SnowPhysics.profile(for: .ice)
        // Scrubbing needs an edge that bites. On ice the ski slides instead of digging,
        // which is the physical reason ice runs fast — a model that scrubbed *more* on
        // low-grip surfaces would have it exactly backwards.
        #expect(ice.speedRetention(carveIntensity: 0.3) > packed.speedRetention(carveIntensity: 0.3))
    }

    @Test("crust rejects landings that powder absorbs")
    func floatDecidesLandings() {
        let awkwardLanding = 0.5 // radians off the slope normal
        #expect(SnowPhysics.profile(for: .powder).absorbsLanding(impactAngle: awkwardLanding))
        #expect(!SnowPhysics.profile(for: .crust).absorbsLanding(impactAngle: awkwardLanding))
    }
}

// MARK: - Colour

@Suite("OKLCH colour")
struct OKLCHTests {

    @Test("white and black convert exactly")
    func convertsAchromaticEndpoints() {
        let white = OKLCH(l: 1, c: 0, h: 0).rgba
        #expect(abs(white.r - 1) < 0.01 && abs(white.g - 1) < 0.01 && abs(white.b - 1) < 0.01)

        let black = OKLCH(l: 0, c: 0, h: 0).rgba
        #expect(black.r < 0.01 && black.g < 0.01 && black.b < 0.01)
    }

    @Test("a known OKLCH coordinate lands on sRGB red")
    func convertsKnownChromaticValue() {
        // Ottosson's published Oklab value for sRGB #FF0000, expressed in polar form.
        let red = OKLCH(l: 0.6280, c: 0.2577, h: 29.23).rgba
        #expect(red.r > 0.97)
        #expect(red.g < 0.06)
        #expect(red.b < 0.06)
    }

    @Test("output is always inside the display gamut")
    func clampsToGamut() {
        // Deliberately out-of-gamut chroma must not produce NaN or out-of-range channels.
        let extreme = OKLCH(l: 0.7, c: 0.9, h: 140).rgba
        for channel in [extreme.r, extreme.g, extreme.b] {
            #expect(channel >= 0 && channel <= 1)
            #expect(!channel.isNaN)
        }
    }

    @Test("hue blending takes the short way around the circle")
    func blendsHueShortestPath() {
        let from = OKLCH(l: 0.5, c: 0.1, h: 350)
        let to = OKLCH(l: 0.5, c: 0.1, h: 10)
        let middle = from.blended(toward: to, amount: 0.5)
        // Must pass through 0°, not sweep backwards through green at 180°.
        let normalised = (middle.h + 360).truncatingRemainder(dividingBy: 360)
        #expect(normalised > 355 || normalised < 5)
    }
}

// MARK: - Palette

@Suite("Scene palette")
struct ScenePaletteTests {

    @Test("night is darker than noon")
    func exposureTracksSun() {
        let night = PaletteGenerator.palette(for: mountain(sunAltitudeDeg: -20), state: .packed)
        let noon = PaletteGenerator.palette(for: mountain(sunAltitudeDeg: 60), state: .packed)
        #expect(night.exposure < noon.exposure)
        #expect(night.skyZenith.l < noon.skyZenith.l)
    }

    @Test("a whiteout dissolves distance almost completely")
    func lowVisibilityRaisesDepthDissolve() {
        let clear = PaletteGenerator.palette(for: mountain(visibilityM: 20_000), state: .packed)
        let whiteout = PaletteGenerator.palette(for: mountain(visibilityM: 60), state: .powder)
        #expect(whiteout.depthDissolve > clear.depthDissolve)
        #expect(whiteout.depthDissolve > 0.85)
    }

    @Test("overcast drains colour without simply going dark")
    func cloudDesaturates() {
        let clear = PaletteGenerator.palette(for: mountain(cloudCoverPercent: 0), state: .packed)
        let overcast = PaletteGenerator.palette(for: mountain(cloudCoverPercent: 100), state: .packed)
        #expect(overcast.skyZenith.c < clear.skyZenith.c)
    }

    @Test("shadowed snow takes the sky's hue, not grey")
    func shadowsAreSkyLit() {
        let palette = PaletteGenerator.palette(for: mountain(sunAltitudeDeg: 40), state: .packed)
        // Chroma above zero and hue matching the zenith is what makes alpine shadows read
        // blue rather than muddy — the single biggest tell of convincing snow rendering.
        #expect(palette.snowShadow.c > 0.01)
        #expect(abs(palette.snowShadow.h - palette.skyZenith.h) < 1)
    }

    @Test("every weather combination produces a renderable palette")
    func paletteIsTotal() {
        for sun in stride(from: -25.0, through: 80, by: 7) {
            for cloud in stride(from: 0.0, through: 100, by: 25) {
                for state in SnowState.allCases {
                    let palette = PaletteGenerator.palette(
                        for: mountain(cloudCoverPercent: cloud, sunAltitudeDeg: sun),
                        state: state
                    )
                    let sky = palette.skyZenith.rgba
                    #expect(!sky.r.isNaN && !sky.g.isNaN && !sky.b.isNaN)
                    #expect(palette.exposure > 0 && palette.exposure <= 1)
                }
            }
        }
    }
}

// MARK: - Terrain

@Suite("Terrain generation")
struct TerrainTests {

    @Test("the same seed always produces the same mountain")
    func isDeterministic() {
        let a = TerrainGenerator(seed: 555, snowState: .packed)
        let b = TerrainGenerator(seed: 555, snowState: .packed)
        for step in 0..<400 {
            let x = Double(step) * 3.7
            #expect(a.height(at: x) == b.height(at: x))
        }
    }

    @Test("different seeds produce different mountains")
    func seedsDiverge() {
        let a = TerrainGenerator(seed: 1, snowState: .packed)
        let b = TerrainGenerator(seed: 2, snowState: .packed)
        let differences = (0..<200).filter { step in
            let x = Double(step) * 5
            return abs(a.height(at: x) - b.height(at: x)) > 0.5
        }
        #expect(differences.count > 150)
    }

    @Test("the slope descends overall")
    func trendsDownhill() {
        let terrain = TerrainGenerator(seed: 42, snowState: .packed)
        #expect(terrain.height(at: 5_000) < terrain.height(at: 0))
    }

    @Test("far terrain is reachable without generating everything before it")
    func supportsRandomAccess() {
        let direct = TerrainGenerator(seed: 77, snowState: .packed).height(at: 250_000)
        let walked = TerrainGenerator(seed: 77, snowState: .packed)
        for step in 0..<100 { _ = walked.height(at: Double(step)) }
        #expect(walked.height(at: 250_000) == direct)
    }

    @Test("snow state changes surface roughness for the same seed")
    func snowStateReachesIntoGeometry() {
        let powder = TerrainGenerator(seed: 9, snowState: .powder)
        let slab = TerrainGenerator(seed: 9, snowState: .windSlab)

        /// Mean absolute curvature — the second difference of the height field.
        ///
        /// Measured as raw step-to-step change instead, the constant descent gradient
        /// contributes roughly 80% of the total and buries the signal being tested. The
        /// second difference cancels every linear term by construction, so what is left
        /// is purely surface texture.
        func roughness(_ terrain: TerrainGenerator) -> Double {
            let step = 0.3
            let samples = 1..<400
            let total = samples.reduce(0.0) { running, index in
                let x = Double(index) * step
                let curvature = terrain.height(at: x + step)
                    - 2 * terrain.height(at: x)
                    + terrain.height(at: x - step)
                return running + abs(curvature)
            }
            return total / Double(samples.count)
        }

        // Fresh snow fills and smooths; wind sculpts sastrugi. Same seed, different surface.
        #expect(roughness(slab) > roughness(powder) * 2)
    }
}

// MARK: - Location bucketing

@Suite("Location bucketing")
struct LocationBucketTests {

    @Test("encodes known coordinates correctly")
    func matchesReferenceGeohashes() {
        #expect(LocationBucket.encode(latitude: 57.64911, longitude: 10.40744, precision: 5) == "u4pru")
        #expect(LocationBucket.encode(latitude: 37.7749, longitude: -122.4194, precision: 4) == "9q8y")
    }

    @Test("nearby players share a bucket, distant ones do not")
    func bucketsByLocality() {
        let downtown = LocationBucket(latitude: 45.9237, longitude: 6.8694)   // Chamonix
        let nextStreet = LocationBucket(latitude: 45.9251, longitude: 6.8702)
        let farAway = LocationBucket(latitude: 46.5197, longitude: 6.6323)    // Lausanne

        #expect(downtown.geohash == nextStreet.geohash)
        #expect(downtown.geohash != farAway.geohash)
    }

    @Test("precise coordinates never survive bucketing")
    func discardsPreciseLocation() {
        // The privacy guarantee: what leaves the device is a cell centre, never the input.
        let precise = LocationBucket(latitude: 45.923765, longitude: 6.869433)
        #expect(precise.latitude != 45.923765)
        #expect(abs(precise.latitude - 45.923765) < 0.3)
    }
}

// MARK: - Run assembly

@Suite("Run conditions")
struct RunConditionsTests {

    @Test("players in the same place and hour ski the same mountain")
    func seedIsStableWithinAnHour() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let shortlyAfter = now.addingTimeInterval(600)

        let first = RunConditions.resolve(from: station(), placeName: "Chamonix", bucketKey: "u0m8", at: now)
        let second = RunConditions.resolve(from: station(), placeName: "Chamonix", bucketKey: "u0m8", at: shortlyAfter)

        // Required for honest comparison: two friends in the same town must race identical terrain.
        #expect(first.seed == second.seed)
    }

    @Test("a different hour brings a new mountain")
    func seedRotatesHourly() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let nextHour = now.addingTimeInterval(3_700)

        let first = RunConditions.resolve(from: station(), placeName: "Chamonix", bucketKey: "u0m8", at: now)
        let second = RunConditions.resolve(from: station(), placeName: "Chamonix", bucketKey: "u0m8", at: nextHour)
        #expect(first.seed != second.seed)
    }

    @Test("different places get different mountains")
    func seedVariesByPlace() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let alps = RunConditions.resolve(from: station(), placeName: "Chamonix", bucketKey: "u0m8", at: now)
        let rockies = RunConditions.resolve(from: station(), placeName: "Aspen", bucketKey: "9xj5", at: now)
        #expect(alps.seed != rockies.seed)
    }

    @Test("physics and palette always agree with the classified state")
    func componentsAreConsistent() {
        let conditions = RunConditions.resolve(
            from: station(temperatureC: -2, precipitation24hMm: 25, freezingLevelM: 500),
            placeName: "Test",
            bucketKey: "test"
        )
        #expect(conditions.physics == SnowPhysics.profile(for: conditions.snowState))
        #expect(!conditions.headline.isEmpty)
    }

    @Test("fallback conditions are playable without any network")
    func fallbackIsValid() {
        let fallback = RunConditions.fallback()
        // A weather game that refuses to start without weather has confused its input for
        // its product. Offline must always be playable.
        #expect(fallback.weather.temperatureC < 0)
        #expect(fallback.palette.exposure > 0)
        #expect(!fallback.headline.isEmpty)
    }

    @Test("conditions go stale on the refresh interval")
    func staleness() {
        let fresh = RunConditions.fallback(at: Date())
        let old = RunConditions.fallback(at: Date().addingTimeInterval(-1_000))
        #expect(!fresh.isStale)
        #expect(old.isStale)
    }
}
