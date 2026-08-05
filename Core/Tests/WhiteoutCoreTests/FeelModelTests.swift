import Testing
import Foundation
@testable import WhiteoutCore

private func skier(
    velocityX: Double = 20,
    velocityY: Double = 0,
    grounded: Bool = true,
    crashed: Bool = false,
    instability: Double = 0
) -> SkierState {
    SkierState(
        distanceM: 500, altitudeM: 0,
        velocityX: velocityX, velocityY: velocityY,
        rotation: 0, angularVelocity: 0,
        isGrounded: grounded, hasCrashed: crashed,
        airTimeS: 0, totalAirTimeS: 0, flips: 0, jumpRotation: 0,
        instability: instability
    )
}

private func weather(windSpeedKmh: Double = 15) -> MountainWeather {
    MountainWeather(
        elevationM: 2_800, temperatureC: -5, freshSnowCm: 4, snowfallCmPerHour: 0,
        isRainingAtAltitude: false,
        windSpeedKmh: windSpeedKmh, windGustKmh: windSpeedKmh * 1.5, windDirectionDeg: 270,
        visibilityM: 8_000, cloudCoverPercent: 40, sunAltitudeDeg: 25, localHour: 11,
        maxTemperature24hC: -3, minTemperature24hC: -9
    )
}

@Suite("Feel cues")
struct FeelModelTests {

    private func cues(
        _ state: SkierState,
        snow: SnowState = .packed,
        tucking: Bool = false,
        wind: Double = 15
    ) -> FeelCues {
        FeelModel.cues(
            for: state,
            physics: SnowPhysics.profile(for: snow),
            weather: weather(windSpeedKmh: wind),
            isTucking: tucking
        )
    }

    @Test("rough snow shakes the screen and smooth snow does not")
    func shakeTracksSurface() {
        let fast = skier(velocityX: 25)
        // The whole point of the pass: the snowpack has to be felt, not read off a meter.
        #expect(cues(fast, snow: .ice).shake > cues(fast, snow: .powder).shake)
        #expect(cues(fast, snow: .crust).shake > cues(fast, snow: .packed).shake)
    }

    @Test("shake grows with speed, not just with surface")
    func shakeTracksSpeed() {
        #expect(cues(skier(velocityX: 24), snow: .crust).shake > cues(skier(velocityX: 8), snow: .crust).shake)
    }

    @Test("a failing edge buzzes before the meter fills")
    func instabilityWarns() {
        let calm = cues(skier(velocityX: 20, instability: 0.2), snow: .powder)
        let losingIt = cues(skier(velocityX: 20, instability: 0.92), snow: .powder)
        // Powder barely shakes on its own, so this isolates the warning channel: the
        // player should feel the edge going before they have time to read the HUD.
        #expect(losingIt.shake > calm.shake + 0.2)
    }

    @Test("the warning stays quiet until the edge is genuinely at risk")
    func warningHasADeadZone() {
        let early = cues(skier(velocityX: 20, instability: 0.5), snow: .powder)
        // A cue that fires constantly stops being a cue.
        #expect(early.shake < 0.1)
    }

    @Test("the air goes quiet")
    func airIsCalm() {
        let airborne = skier(velocityX: 25, velocityY: 8, grounded: false)
        #expect(cues(airborne, snow: .ice).shake == 0)
        // Contrast against a rough surface is what makes a jump read as relief.
        #expect(cues(skier(velocityX: 25), snow: .ice).shake > 0.3)
    }

    @Test("a crash stops shaking rather than shaking hardest")
    func crashIsStill() {
        #expect(cues(skier(velocityX: 4, crashed: true), snow: .ice).shake == 0)
    }

    @Test("wind noise responds to how fast you are moving, not just the forecast")
    func windUsesApparentSpeed() {
        // Bombing a calm slope must still roar; a forecast-only model would be silent.
        let fastInStillAir = cues(skier(velocityX: 25), wind: 0)
        let slowInAGale = cues(skier(velocityX: 3), wind: 60)
        #expect(fastInStillAir.windLevel > 0.6)
        #expect(slowInAGale.windLevel > 0.2)
    }

    @Test("edge noise only plays while actually carving")
    func carveAudioFollowsInput() {
        #expect(cues(skier(), tucking: false).carveLevel > 0)
        #expect(cues(skier(), tucking: true).carveLevel == 0)
        #expect(cues(skier(grounded: false), tucking: false).carveLevel == 0)
        #expect(cues(skier(crashed: true), tucking: false).carveLevel == 0)
    }

    @Test("speed lines stay off at cruising speed")
    func speedLinesHaveAThreshold() {
        #expect(cues(skier(velocityX: 10)).speedLines == 0)
        #expect(cues(skier(velocityX: 26)).speedLines > 0.5)
    }

    @Test("camera lead rises with speed")
    func cameraLooksAheadWhenFast() {
        #expect(cues(skier(velocityX: 26)).cameraLead > cues(skier(velocityX: 9)).cameraLead)
    }

    @Test("landing impact fires once, scaled by vertical speed")
    func landingImpactIsAnEvent() {
        let falling = skier(velocityY: -14, grounded: false)
        let landed = skier(grounded: true)

        let hard = FeelModel.landingImpact(previous: falling, current: landed)
        #expect(hard > 0.5)

        let soft = FeelModel.landingImpact(previous: skier(velocityY: -2, grounded: false), current: landed)
        #expect(soft < hard)

        // Must not re-fire on subsequent grounded frames, or the camera punches forever.
        #expect(FeelModel.landingImpact(previous: landed, current: landed) == 0)
    }

    @Test("every cue stays inside its normalised range")
    func cuesAreBounded() {
        for snow in SnowState.allCases {
            for speed in stride(from: 0.0, through: 40, by: 5) {
                for instability in stride(from: 0.0, through: 1.0, by: 0.25) {
                    let result = cues(skier(velocityX: speed, instability: instability), snow: snow, wind: 90)
                    for value in [result.shake, result.speedLines, result.carveLevel, result.windLevel, result.cameraLead] {
                        #expect(value >= 0 && value <= 1)
                        #expect(!value.isNaN)
                    }
                }
            }
        }
    }
}
