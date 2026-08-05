import Testing
import Foundation
@testable import WhiteoutCore

// MARK: - Fixtures

private func sky(
    sunAltitudeDeg: Double,
    cloudCoverPercent: Double = 20,
    visibilityM: Double = 20_000
) -> MountainWeather {
    MountainWeather(
        elevationM: 2_800,
        temperatureC: -5,
        freshSnowCm: 3,
        snowfallCmPerHour: 0,
        isRainingAtAltitude: false,
        windSpeedKmh: 10,
        windGustKmh: 14,
        windDirectionDeg: 300,
        visibilityM: visibilityM,
        cloudCoverPercent: cloudCoverPercent,
        sunAltitudeDeg: sunAltitudeDeg,
        localHour: 12,
        maxTemperature24hC: -3,
        minTemperature24hC: -9
    )
}

/// Deliberately spans the whole solar range, both cloud extremes and a whiteout, because a
/// contrast rule that only holds at midday is not a rule.
private let paletteSweep: [(name: String, weather: MountainWeather, state: SnowState)] = [
    ("alpine noon", sky(sunAltitudeDeg: 65, cloudCoverPercent: 0, visibilityM: 40_000), .packed),
    ("overcast midday", sky(sunAltitudeDeg: 40, cloudCoverPercent: 100, visibilityM: 1_200), .packed),
    ("whiteout", sky(sunAltitudeDeg: 20, cloudCoverPercent: 100, visibilityM: 300), .powder),
    ("golden hour", sky(sunAltitudeDeg: 8), .packed),
    ("sunrise", sky(sunAltitudeDeg: 0), .slush),
    ("civil twilight", sky(sunAltitudeDeg: -6, cloudCoverPercent: 30), .crust),
    ("astronomical night", sky(sunAltitudeDeg: -18, cloudCoverPercent: 0), .ice),
    ("night whiteout", sky(sunAltitudeDeg: -12, cloudCoverPercent: 100, visibilityM: 200), .windSlab)
]

private func palettes() -> [(name: String, palette: ScenePalette)] {
    paletteSweep.map { ($0.name, PaletteGenerator.palette(for: $0.weather, state: $0.state)) }
}

// MARK: - Skeleton

@Suite("Skier rig — skeleton")
struct SkierRigSkeletonTests {

    @Test("the tuck is a genuinely lower silhouette, not a squashed standing one")
    func tuckIsLower() {
        let ratio = SkierRig.tuck.silhouetteHeight / SkierRig.upright.silhouetteHeight
        // A real downhill tuck sits near 55% of standing height. The placeholder faked
        // 68% with a vertical scale, which is both too tall and the wrong shape.
        #expect(ratio < 0.62)
        #expect(ratio > 0.45)
    }

    @Test("the tuck flattens the back into a single readable line")
    func tuckBackIsFlat() {
        let hip = SkierRig.tuck.hip
        let shoulder = SkierRig.tuck.shoulder
        let backAngle = atan2(shoulder.y - hip.y, shoulder.x - hip.x)
        // Racing tuck, not a crouch: the torso is close to parallel with the slope.
        #expect(backAngle < 0.40)
        #expect(backAngle > 0.10)
    }

    @Test("the tuck holds the shins near vertical")
    func tuckShinsAreVertical() {
        let boot = SkierRig.tuck.boot
        let knee = SkierRig.tuck.knee
        let fromVertical = atan2(knee.x - boot.x, knee.y - boot.y)
        #expect(abs(fromVertical) < 0.35)
    }

    @Test("the tuck throws the forearms forward and horizontal")
    func tuckForearmsAreHorizontal() {
        let elbow = SkierRig.tuck.elbow
        let hand = SkierRig.tuck.hand
        #expect(hand.x > elbow.x)
        #expect(abs(hand.y - elbow.y) < 0.05)
    }

    @Test("the tuck drives the hips behind the boots")
    func tuckSeatsTheHipsBack() {
        #expect(SkierRig.tuck.hip.x < SkierRig.upright.hip.x - 0.08)
    }

    @Test("upright proportions stay recognisably human")
    func uprightProportions() {
        let pose = SkierRig.upright
        // Stature landmarks: hip ~0.48, shoulder ~0.78, knee ~0.26.
        #expect(abs(pose.hip.y - 0.48) < 0.06)
        #expect(abs(pose.shoulder.y - 0.78) < 0.06)
        #expect(abs(pose.knee.y - 0.26) < 0.06)
        // The crown lands at 1.0 by construction; that is what normalises the rig.
        #expect(abs(pose.head.y + SkierRig.headRadius - 1.0) < 0.03)
    }

    @Test("the joint chain runs monotonically up the body when standing")
    func uprightChainIsOrdered() {
        let pose = SkierRig.upright
        #expect(pose.boot.y < pose.knee.y)
        #expect(pose.knee.y < pose.hip.y)
        #expect(pose.hip.y < pose.shoulder.y)
        #expect(pose.shoulder.y < pose.head.y)
    }

    // Ski span, bone rigidity and the head/shoulder overlap now hold across *all eight*
    // authored poses and at every point between any two of them, so those assertions live
    // in `RigAnglesTests` where they can be made against blended poses as well.

    @Test("the head is never wider than the torso")
    func headIsNotALollipop() {
        #expect(SkierRig.headRadius * 2 < SkierRig.Width.core)
    }

    @Test("a crash collapses the body onto the skis")
    func collapsedIsLow() {
        #expect(SkierRig.collapsed.silhouetteHeight < SkierRig.tuck.silhouetteHeight)
    }
}

// MARK: - Posing

@Suite("Skier rig — posing")
struct SkierRigPosingTests {

    private func cues(tuck: Double) -> FeelCues {
        FeelCues(
            cameraLead: 0, shake: 0, speedLines: 0,
            carveLevel: 0, windLevel: 0, tuckCompression: tuck
        )
    }

    private func state(
        grounded: Bool = true,
        crashed: Bool = false
    ) -> SkierState {
        SkierState(
            distanceM: 100, altitudeM: -30, velocityX: 18, velocityY: -5,
            rotation: -0.3, angularVelocity: 0,
            isGrounded: grounded, hasCrashed: crashed,
            airTimeS: 0, totalAirTimeS: 0, flips: 0, jumpRotation: 0,
            instability: 0.2
        )
    }

    @Test("a held tuck reaches the tuck pose exactly")
    func fullTuckMatches() {
        let pose = SkierRig.pose(for: state(), cues: cues(tuck: 1))
        #expect(pose == SkierRig.tuck)
    }

    @Test("standing up reaches the upright pose exactly")
    func noTuckMatches() {
        let pose = SkierRig.pose(for: state(), cues: cues(tuck: 0))
        #expect(pose == SkierRig.upright)
    }

    @Test("a partial tuck lands between the two poses")
    func partialTuckInterpolates() {
        let pose = SkierRig.pose(for: state(), cues: cues(tuck: 0.5))
        let height = pose.silhouetteHeight
        #expect(height < SkierRig.upright.silhouetteHeight)
        #expect(height > SkierRig.tuck.silhouetteHeight)
    }

    @Test("leaving the ground switches to the air pose regardless of input")
    func airborneOverridesTuck() {
        #expect(SkierRig.pose(for: state(grounded: false), cues: cues(tuck: 1)) == SkierRig.airborne)
        #expect(SkierRig.pose(for: state(grounded: false), cues: cues(tuck: 0)) == SkierRig.airborne)
    }

    @Test("a crash collapses whatever the skier was doing")
    func crashOverridesEverything() {
        #expect(SkierRig.pose(for: state(crashed: true), cues: cues(tuck: 1)) == SkierRig.collapsed)
        #expect(
            SkierRig.pose(for: state(grounded: false, crashed: true), cues: cues(tuck: 0))
                == SkierRig.collapsed
        )
    }

    @Test("the idle cue produces a standing skier on the frame before the run starts")
    func idleIsUpright() {
        #expect(SkierRig.pose(for: SkierState.start(on: TerrainGenerator(seed: 1, snowState: .packed)),
                              cues: .idle) == SkierRig.upright)
    }

    @Test("the flip pose is markedly more compact than simply being airborne")
    func flipTuckBallsUp() {
        // If the two read the same, a backflip is a rotating sprite and the rotation is
        // carrying the entire read on its own.
        #expect(SkierRig.flipTuck.silhouetteHeight < SkierRig.airborne.silhouetteHeight * 0.85)
        // Knees drawn up toward the chest, not just a lower stance.
        #expect(SkierRig.flipTuck.knee.y > SkierRig.flipTuck.hip.y - 0.06)
        #expect(SkierRig.flipTuck.boot.x > SkierRig.airborne.boot.x)
    }

    @Test("the landing pose absorbs deeply without becoming a tuck")
    func landingAbsorbs() {
        // Deep enough to read as taking a hit, open enough that it is never mistaken for
        // the racing egg — the two mean opposite things about what the player just did.
        let landing = SkierRig.landing.silhouetteHeight
        #expect(landing < SkierRig.upright.silhouetteHeight * 0.88)
        #expect(landing > SkierRig.tuck.silhouetteHeight * 1.25)
        // Chest up and hands forward for balance, unlike the tuck's head-down egg.
        #expect(SkierRig.landing.head.y > SkierRig.tuck.head.y)
    }

    @Test("the carve pair straddles the standing pose, so the rhythm reads as flex and extend")
    func carvePairStraddlesUpright() {
        let upright = SkierRig.upright.silhouetteHeight
        #expect(SkierRig.carveLeft.silhouetteHeight < upright)
        #expect(SkierRig.carveRight.silhouetteHeight > upright)

        // The bob alone is only 10% of body height. What sells the rhythm at this size is
        // the pole tip, swinging roughly three times as far as the body travels.
        let poleTravel = hypot(
            SkierRig.carveRight.poleTip.x - SkierRig.carveLeft.poleTip.x,
            SkierRig.carveRight.poleTip.y - SkierRig.carveLeft.poleTip.y
        )
        let bodyTravel = SkierRig.carveRight.silhouetteHeight - SkierRig.carveLeft.silhouetteHeight
        #expect(poleTravel > bodyTravel * 2.5)
    }
}

// MARK: - Legibility

@Suite("Skier rig — legibility")
struct SkierLegibilityTests {

    /// The skier must separate from a backdrop by either its body or its rim.
    ///
    /// Not both, deliberately. At alpine noon the rim is nearly the same lightness as the
    /// sky and the dark body does the work; at night the body is nearly the same lightness
    /// as the sky and the rim does it. Requiring both would be unsatisfiable.
    private func separates(_ palette: ScenePalette, from backdrop: OKLCH) -> Double {
        max(
            abs(palette.skierBody.l - backdrop.l),
            abs(palette.skierRim.l - backdrop.l)
        )
    }

    @Test("the skier reads against the near ridge — the backdrop it is actually on")
    func readsAgainstNearRidge() {
        // This is the case that was genuinely broken, and it took measuring the scene's own
        // layout to find it. The skier stands at 0.34 of screen height and the nearest ridge
        // band fills everything below 0.55, so that band — not the sky, and not the snow it
        // stands on — is what the body is seen against for the whole run.
        let depth = ScenePalette.skierBackdropDepth
        for (name, palette) in palettes() {
            // The band is a vertical gradient, so both ends have to clear the floor.
            for (edge, backdrop) in [
                ("crest", palette.ridgeCrest(depth: depth)),
                ("base", palette.ridgeBase(depth: depth)),
                ("mid", palette.ridge(depth: depth))
            ] {
                let gap = separates(palette, from: backdrop)
                #expect(gap >= PaletteGenerator.skierContrastFloor, "\(name)/\(edge) gap \(gap)")
            }
        }
    }

    @Test("the skier reads against the snow at its feet")
    func readsAgainstSnow() {
        for (name, palette) in palettes() {
            for (surface, backdrop) in [("shadow", palette.snowShadow), ("lit", palette.snowLit)] {
                let gap = separates(palette, from: backdrop)
                #expect(gap >= PaletteGenerator.skierContrastFloor, "\(name)/\(surface) gap \(gap)")
            }
        }
    }

    @Test("the two tones straddle the lightness axis, so no backdrop can hide both")
    func tonesStraddleTheAxis() {
        // The guarantee behind every case above. A backdrop can be close to one tone or the
        // other, never to both, as long as the pair stays this far apart.
        for (name, palette) in palettes() {
            let spread = palette.skierRim.l - palette.skierBody.l
            #expect(spread >= 0.60, "\(name) spread only \(spread)")
        }
    }

    @Test("the body is always darker than the snow it stands on")
    func bodyIsDarkerThanSnow() {
        for (name, palette) in palettes() {
            #expect(palette.skierBody.l < palette.snowShadow.l, "\(name)")
            #expect(palette.skierBody.l < palette.snowLit.l, "\(name)")
        }
    }

    @Test("the rim is always lighter than the body")
    func rimIsLighterThanBody() {
        for (name, palette) in palettes() {
            #expect(palette.skierRim.l > palette.skierBody.l + 0.2, "\(name)")
        }
    }

    @Test("the body never reaches pure black, which reads as a hole rather than a person")
    func bodyIsNeverBlack() {
        for (name, palette) in palettes() {
            #expect(palette.skierBody.l >= 0.06, "\(name)")
        }
    }

    @Test("the skier's colours stay inside the sRGB gamut")
    func coloursAreRenderable() {
        for (name, palette) in palettes() {
            for colour in [palette.skierBody, palette.skierRim] {
                let rgb = colour.rgba
                #expect(rgb.r >= 0 && rgb.r <= 1, "\(name)")
                #expect(rgb.g >= 0 && rgb.g <= 1, "\(name)")
                #expect(rgb.b >= 0 && rgb.b <= 1, "\(name)")
            }
        }
    }
}
