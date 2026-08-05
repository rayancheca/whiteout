import SpriteKit
import WhiteoutCore

/// Renders one run.
///
/// Holds no art assets. Every colour comes from `ScenePalette`, every contour from
/// `TerrainGenerator`, and both are functions of the weather. Changing the weather changes
/// the entire look and feel with no new files — which is the only way a game whose content
/// is "the actual atmosphere" can cover a continuous range of conditions.
final class MountainScene: SKScene {

    // MARK: Layout constants

    private let pointsPerMetre: CGFloat = 2.0
    /// Where the skier sits horizontally when cruising, and when flat out.
    /// Moving them back at speed buys sightline exactly when it is needed most.
    private let skierXCruising: CGFloat = 0.34
    private let skierXFlatOut: CGFloat = 0.20
    private let horizonFraction: CGFloat = 0.52
    /// Horizontal sample spacing when tessellating the slope, in points.
    private let terrainSampleStep: CGFloat = 4

    // MARK: State

    private let conditions: RunConditions
    private let terrain: TerrainGenerator
    private let telemetry: RunTelemetry

    /// The whole of the world's mutable state. Every frame derives a new one.
    private var skier: SkierState
    private var isHolding = false
    private var lastFrameTime: TimeInterval = 0

    private var cues: FeelCues = .idle
    /// Lagged camera height. Following terrain exactly pins the skier to a fixed pixel and
    /// the mountain stops registering as terrain at all; a lag lets crests lift them.
    private var cameraHeightM: Double
    /// Decaying downward camera offset from a landing.
    private var landingPunch: CGFloat = 0
    /// Recent positions, for the ski trail.
    private var trail: [(distance: Double, altitude: Double)] = []

    private var distanceMetres: Double { skier.distanceM }
    private var skierScreenXFraction: CGFloat {
        skierXCruising + (skierXFlatOut - skierXCruising) * CGFloat(cues.cameraLead)
    }

    // MARK: Nodes

    private var skyLayer = SKSpriteNode()
    private var ridgeLayers: [RidgeLayer] = []
    private var slopeNode = SKShapeNode()
    private var slopeEdgeNode = SKShapeNode()
    private var skierNode = SKShapeNode()
    private var trailNode = SKShapeNode()
    private var snowfallNode: SKEmitterNode?
    private var sprayNode: SKEmitterNode?
    private var speedLinesNode: SKEmitterNode?

    /// Everything that shakes. Sky, weather and grain stay outside it — shaking the
    /// atmosphere along with the ground reads as a camera fault rather than as rough snow.
    private let worldNode = SKNode()

    private let feedback = RunFeedback()

    /// One parallax band of distant mountains.
    private struct RidgeLayer {
        let node: SKShapeNode
        /// The lit snowline along the top of the band.
        let crest: SKShapeNode
        /// 0 = pinned to the horizon, 1 = moves with the player.
        let parallax: CGFloat
        let noise: SeededRandom
        let frequency: Double
        let amplitude: CGFloat
        let baseHeight: CGFloat
        /// How far this band has dissolved into atmosphere.
        let depth: CGFloat
    }

    init(conditions: RunConditions, telemetry: RunTelemetry, size: CGSize) {
        self.conditions = conditions
        self.telemetry = telemetry
        let terrain = TerrainGenerator(seed: conditions.seed, snowState: conditions.snowState)
        self.terrain = terrain
        self.skier = SkierState.start(on: terrain)
        self.cameraHeightM = terrain.height(at: 0)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    // MARK: - Input

    // One input, held or not. What the correct hold pattern *is* changes entirely with
    // the day's snowpack, which is where the weather stops being scenery.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if skier.hasCrashed {
            restart()
        } else {
            isHolding = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHolding = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHolding = false
    }

    private func restart() {
        skier = SkierState.start(on: terrain)
        isHolding = false
        telemetry.update(from: skier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = conditions.palette.skyHorizon.uiColor
        addChild(worldNode)
        buildSky()
        buildSunGlow()
        buildRidges()
        buildSlope()
        buildTrail()
        buildSkier()
        buildSpray()
        buildSpeedLines()
        buildSnowfall()
        buildGrain()
        feedback.start()
    }

    override func willMove(from view: SKView) {
        feedback.stop()
    }

    /// The line the skier has carved, drawn behind them.
    ///
    /// Cheap, and it does a job nothing else does: it makes the player's own choices
    /// visible. Without it a run leaves no evidence, and the terrain reads as something
    /// happening *to* the player rather than something they picked a line through.
    private func buildTrail() {
        trailNode.removeFromParent()
        trailNode = SKShapeNode()
        trailNode.lineWidth = 2
        trailNode.fillColor = .clear
        trailNode.strokeColor = conditions.palette.snowShadow.uiColor
            .mixed(with: .black, amount: 0.35)
            .withAlphaComponent(0.7)
        trailNode.lineCap = .round
        trailNode.zPosition = 12
        worldNode.addChild(trailNode)
    }

    /// Horizontal streaks at high speed. Off entirely below the threshold.
    private func buildSpeedLines() {
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: streakImage())
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 0.5
        emitter.particlePositionRange = CGVector(dx: 0, dy: size.height * 0.9)
        emitter.position = CGPoint(x: size.width + 30, y: size.height * 0.5)
        // Streaming against the direction of travel, since the world scrolls past a
        // skier who stays put on screen.
        emitter.emissionAngle = .pi
        emitter.particleSpeed = 1_400
        emitter.particleSpeedRange = 600
        emitter.particleAlpha = 0.30
        emitter.particleAlphaSpeed = -0.7
        emitter.particleScale = 1
        emitter.particleScaleRange = 0.5
        emitter.particleColor = conditions.palette.snowLit.uiColor
        emitter.particleColorBlendFactor = 1
        emitter.zPosition = 40
        worldNode.addChild(emitter)
        speedLinesNode = emitter
    }

    private func streakImage() -> UIImage {
        let canvas = CGSize(width: 34, height: 2)
        return UIGraphicsImageRenderer(size: canvas).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: canvas))
        }
    }

    /// Atmospheric scattering around the sun.
    ///
    /// Flat vector skies read as illustration; a soft bloom where the light actually comes
    /// from is what makes the same geometry read as air. Suppressed under heavy cloud,
    /// because an overcast sky has no visible sun to bloom around.
    private func buildSunGlow() {
        let palette = conditions.palette
        let cloudCover = min(max(conditions.weather.cloudCoverPercent / 100, 0), 1)
        let strength = CGFloat(palette.exposure) * (1 - cloudCover * 0.85)
        guard strength > 0.05 else { return }

        let diameter = size.width * 1.1
        let glow = SKSpriteNode(
            texture: SKTexture(image: radialGlowImage(diameter: diameter, colour: palette.light.uiColor))
        )
        // The sun tracks east-to-west across the day, so the bloom sits where the light
        // physically is rather than always dead centre.
        let dayProgress = min(max((conditions.weather.localHour - 6) / 12, 0), 1)
        glow.position = CGPoint(
            x: size.width * CGFloat(dayProgress),
            y: size.height * horizonFraction
        )
        glow.size = CGSize(width: diameter, height: diameter)
        glow.alpha = min(0.55, strength * 0.6)
        glow.blendMode = .add
        glow.zPosition = -90
        addChild(glow)
    }

    private func radialGlowImage(diameter: CGFloat, colour: UIColor) -> UIImage {
        let canvas = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: canvas).image { context in
            let colours = [
                colour.withAlphaComponent(0.85).cgColor,
                colour.withAlphaComponent(0.20).cgColor,
                colour.withAlphaComponent(0).cgColor
            ]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours as CFArray,
                locations: [0, 0.35, 1]
            ) else { return }

            let centre = CGPoint(x: diameter / 2, y: diameter / 2)
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: diameter / 2,
                options: []
            )
        }
    }

    /// Fine film grain across the whole frame.
    ///
    /// The single cheapest cue that separates "rendered illustration" from "photographed
    /// place". Kept very low in alpha — it should be felt rather than seen, and it also
    /// hides the banding that large smooth gradients produce on an OLED panel.
    private func buildGrain() {
        // Low smoothness gives fine per-pixel grain. Higher values cluster the noise into
        // visible blotches that read as a dirty lens rather than as film stock.
        let grain = SKSpriteNode(
            texture: SKTexture(noiseWithSmoothness: 0.05, size: size, grayscale: true)
        )
        grain.size = size
        grain.position = CGPoint(x: size.width / 2, y: size.height / 2)
        grain.alpha = 0.035
        grain.blendMode = .screen
        grain.zPosition = 900
        addChild(grain)
    }

    private func buildSky() {
        skyLayer.removeFromParent()
        skyLayer = SKSpriteNode(texture: SKTexture(image: skyGradientImage()))
        skyLayer.anchorPoint = .zero
        skyLayer.position = .zero
        skyLayer.size = size
        skyLayer.zPosition = -100
        addChild(skyLayer)
    }

    /// Draws the sky as a vertical gradient between the palette's zenith and horizon.
    private func skyGradientImage() -> UIImage {
        let palette = conditions.palette
        // One point wide: SpriteKit stretches it horizontally for free, and a 1×H texture
        // costs nothing to upload compared with a full-screen bitmap.
        let gradientSize = CGSize(width: 1, height: max(size.height, 2))

        return UIGraphicsImageRenderer(size: gradientSize).image { context in
            let colours = [palette.skyZenith.uiColor.cgColor, palette.skyHorizon.uiColor.cgColor]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours as CFArray,
                locations: [0, 1]
            ) else { return }

            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: gradientSize.height),
                options: []
            )
        }
    }

    /// Builds the distant mountain bands.
    ///
    /// Each band is tinted toward the atmosphere colour in proportion to its depth — aerial
    /// perspective. Because the blend amount is driven by `palette.depthDissolve`, which is
    /// itself derived from visibility, falling snow physically flattens the range into
    /// silhouettes instead of merely drawing snowflakes over it.
    private func buildRidges() {
        ridgeLayers.forEach {
            $0.node.removeFromParent()
            $0.crest.removeFromParent()
        }

        let root = SeededRandom(seed: conditions.seed).domain("ridges")
        let specifications: [(parallax: CGFloat, frequency: Double, amplitude: CGFloat, base: CGFloat, depth: CGFloat)] = [
            (0.06, 0.0022, 62, 0.30, 0.92),
            (0.14, 0.0041, 48, 0.20, 0.68),
            (0.28, 0.0075, 36, 0.11, 0.42)
        ]

        ridgeLayers = specifications.enumerated().map { index, spec in
            let base = ridgeColour(depth: spec.depth)

            let node = SKShapeNode()
            node.lineWidth = 0
            node.zPosition = CGFloat(-50 + index * 2)
            // A vertical gradient rather than a flat fill. Real ridges are lit along their
            // upper faces and sink into shadow at the base; a single flat colour per band
            // is the tell that reads as clip-art.
            node.fillTexture = SKTexture(image: verticalGradientImage(
                top: base.mixed(with: conditions.palette.snowLit.uiColor, amount: 0.28 * (1 - spec.depth * 0.5)),
                bottom: base.mixed(with: .black, amount: 0.22)
            ))
            node.fillColor = .white
            worldNode.addChild(node)

            // Snow catching light along the crest. Fades with depth, since aerial
            // perspective washes out highlights before it washes out mass.
            let crest = SKShapeNode()
            crest.lineWidth = 2
            crest.fillColor = .clear
            crest.strokeColor = conditions.palette.snowLit.uiColor
                .withAlphaComponent(0.55 * (1 - spec.depth * 0.75))
            crest.zPosition = CGFloat(-50 + index * 2 + 1)
            worldNode.addChild(crest)

            return RidgeLayer(
                node: node,
                crest: crest,
                parallax: spec.parallax,
                noise: root.domain("band\(index)"),
                frequency: spec.frequency,
                amplitude: spec.amplitude,
                baseHeight: spec.base,
                depth: spec.depth
            )
        }
    }

    private func verticalGradientImage(top: UIColor, bottom: UIColor) -> UIImage {
        // 1 point wide; SpriteKit stretches it across the fill for free.
        let canvas = CGSize(width: 1, height: max(size.height, 2))
        return UIGraphicsImageRenderer(size: canvas).image { context in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [bottom.cgColor, top.cgColor] as CFArray,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: canvas.height),
                options: []
            )
        }
    }

    private func ridgeColour(depth: CGFloat) -> UIColor {
        let palette = conditions.palette
        let dissolve = min(0.98, CGFloat(palette.depthDissolve) * depth)
        return palette.rockNear.uiColor.mixed(with: palette.atmosphere.uiColor, amount: dissolve)
    }

    private func buildSlope() {
        slopeNode.removeFromParent()
        slopeEdgeNode.removeFromParent()

        slopeNode = SKShapeNode()
        slopeNode.lineWidth = 0
        slopeNode.fillColor = conditions.palette.snowShadow.uiColor
        slopeNode.zPosition = 10
        worldNode.addChild(slopeNode)

        // A bright rim along the surface itself. Snow is a near-perfect diffuse reflector,
        // so the lit surface reads as the light colour while the mass beneath it is
        // sky-lit and blue — that contrast is most of what makes snow look like snow.
        slopeEdgeNode = SKShapeNode()
        slopeEdgeNode.lineWidth = 3
        slopeEdgeNode.strokeColor = conditions.palette.snowLit.uiColor
        slopeEdgeNode.fillColor = .clear
        slopeEdgeNode.zPosition = 11
        worldNode.addChild(slopeEdgeNode)
    }

    private func buildSkier() {
        skierNode.removeFromParent()

        let body = CGRect(x: -5, y: 0, width: 10, height: 20)
        skierNode = SKShapeNode(path: CGPath(roundedRect: body, cornerWidth: 5, cornerHeight: 5, transform: nil))
        skierNode.fillColor = conditions.palette.rockNear.uiColor.mixed(with: .black, amount: 0.45)
        skierNode.lineWidth = 0
        skierNode.zPosition = 20
        worldNode.addChild(skierNode)
    }

    /// Snow kicked up by the edges. Birth rate is driven per frame by `updateSpray`.
    private func buildSpray() {
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: flakeImage())
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 0.75
        emitter.particleLifetimeRange = 0.4
        emitter.particleSpeed = 60
        emitter.particleSpeedRange = 45
        // Thrown up and behind, opposite the direction of travel.
        emitter.emissionAngle = .pi * 0.82
        emitter.emissionAngleRange = 0.7
        emitter.particleAlpha = 0.7
        emitter.particleAlphaSpeed = -1.1
        emitter.particleScale = 0.26
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.16
        emitter.particleColor = conditions.palette.snowLit.uiColor
        emitter.particleColorBlendFactor = 1
        emitter.yAcceleration = -140
        emitter.zPosition = 19
        worldNode.addChild(emitter)
        sprayNode = emitter
    }

    /// Falling snow, emitted only when it is actually snowing on the mountain.
    private func buildSnowfall() {
        snowfallNode?.removeFromParent()
        let rate = conditions.weather.snowfallCmPerHour
        guard rate > 0.05 else { return }

        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: flakeImage())
        emitter.particleBirthRate = CGFloat(min(900, 45 + rate * 220))
        emitter.particleLifetime = 6
        emitter.particlePositionRange = CGVector(dx: size.width * 1.6, dy: 0)
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 20)
        emitter.particleSpeed = 90 + CGFloat(rate * 22)
        emitter.particleSpeedRange = 55
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = 0.35
        emitter.particleAlpha = 0.85
        emitter.particleAlphaRange = 0.3
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.3
        emitter.particleColor = conditions.palette.snowLit.uiColor
        emitter.particleColorBlendFactor = 1
        emitter.zPosition = 60

        // Wind pushes the column sideways. Direction is meteorological — the bearing the
        // wind blows *from* — so the horizontal component is negated to get travel direction.
        let windRadians = conditions.weather.windDirectionDeg * .pi / 180
        let drift = -sin(windRadians) * conditions.weather.windSpeedKmh * 1.2
        emitter.xAcceleration = CGFloat(drift)
        emitter.yAcceleration = -30

        addChild(emitter)
        snowfallNode = emitter
    }

    private func flakeImage() -> UIImage {
        let diameter: CGFloat = 8
        return UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        defer { lastFrameTime = currentTime }
        guard lastFrameTime > 0 else { return }

        // Clamp the step so a stall or a breakpoint cannot teleport the player down the
        // hill — and, more importantly, so the fixed-step simulation stays stable.
        let delta = min(currentTime - lastFrameTime, 1.0 / 20)

        let previous = skier
        skier = SkierSimulation.step(
            skier,
            input: SkierInput(isHolding: isHolding),
            terrain: terrain,
            physics: conditions.physics,
            delta: delta
        )
        telemetry.update(from: skier)

        cues = FeelModel.cues(
            for: skier,
            physics: conditions.physics,
            weather: conditions.weather,
            isTucking: isHolding
        )

        let impact = FeelModel.landingImpact(previous: previous, current: skier)
        if impact > 0 {
            landingPunch = 16 * CGFloat(impact)
            feedback.landing(strength: impact)
        }
        if !previous.hasCrashed && skier.hasCrashed {
            feedback.crash()
        }

        advanceCamera(delta: delta)
        recordTrail()

        layoutRidges()
        layoutSlope()
        layoutTrail()
        layoutSkier()
        updateSpray()
        updateSpeedLines()
        applyShake(delta: delta)

        feedback.update(cues: cues, delta: delta)
    }

    /// Eases the camera height toward the surface under the skier.
    ///
    /// The lag is the entire point. Tracking the terrain exactly holds the skier at one
    /// fixed pixel forever, so rolling a crest or dropping into a compression produces no
    /// sensation at all — the mountain scrolls past but is never *felt*.
    private func advanceCamera(delta: Double) {
        let target = terrain.height(at: skier.distanceM)
        let followRate = 2.6
        cameraHeightM += (target - cameraHeightM) * (1 - exp(-followRate * delta))

        // Clamped so a sustained steep pitch cannot walk the skier off screen.
        let maxOffsetM = Double(size.height * 0.22 / pointsPerMetre)
        cameraHeightM = min(max(cameraHeightM, target - maxOffsetM), target + maxOffsetM)

        landingPunch *= CGFloat(exp(-7.5 * delta))
    }

    private func recordTrail() {
        let spacingM = 1.4
        if let last = trail.last, skier.distanceM - last.distance < spacingM { return }
        trail.append((skier.distanceM, skier.altitudeM))
        // Only what is on screen plus a margin; the rest can never be seen.
        let visibleM = Double(size.width / pointsPerMetre) + 30
        trail.removeAll { skier.distanceM - $0.distance > visibleM }
    }

    /// Offsets the world by shake and landing punch.
    private func applyShake(delta: Double) {
        let amplitude = CGFloat(cues.shake) * 7
        // Vertical bias: skis chatter up and down against the snow far more than they
        // wander sideways, and horizontal jitter reads as a broken camera.
        let jitterX = CGFloat.random(in: -0.35...0.35) * amplitude
        let jitterY = CGFloat.random(in: -1...1) * amplitude
        worldNode.position = CGPoint(x: jitterX, y: jitterY - landingPunch)
    }

    private func updateSpeedLines() {
        speedLinesNode?.particleBirthRate = CGFloat(cues.speedLines) * 90
        speedLinesNode?.position = CGPoint(x: size.width + 30, y: size.height * 0.5)
    }

    /// Snow thrown from the edges while carving.
    ///
    /// Density comes from `SnowPhysics.sprayDensity`, so powder erupts and ice barely
    /// marks — the surface is legible at a glance without a readout.
    private func updateSpray() {
        guard let spray = sprayNode else { return }
        let isCarving = skier.isGrounded && !isHolding && !skier.hasCrashed
        let speedFraction = min(1, skier.velocityX / 26)
        spray.particleBirthRate = isCarving
            ? CGFloat(conditions.physics.sprayDensity * 260 * speedFraction)
            : 0
        spray.position = skierNode.position
    }

    private func layoutRidges() {
        let horizonY = size.height * horizonFraction

        for layer in ridgeLayers {
            let fill = CGMutablePath()
            let crest = CGMutablePath()
            let offset = CGFloat(distanceMetres) * layer.parallax * pointsPerMetre
            let base = horizonY + layer.baseHeight * size.height * 0.28

            fill.move(to: CGPoint(x: 0, y: 0))
            var x: CGFloat = 0
            var isFirstSample = true
            while x <= size.width {
                let sampleX = Double((x + offset) / pointsPerMetre)
                let elevation = layer.noise.fbm(at: sampleX, octaves: 4, frequency: layer.frequency, persistence: 0.5)
                let point = CGPoint(x: x, y: base + CGFloat(elevation) * layer.amplitude)

                fill.addLine(to: point)
                if isFirstSample {
                    crest.move(to: point)
                    isFirstSample = false
                } else {
                    crest.addLine(to: point)
                }
                x += 6
            }
            fill.addLine(to: CGPoint(x: size.width, y: 0))
            fill.closeSubpath()

            layer.node.path = fill
            layer.crest.path = crest
        }
    }

    private func layoutSlope() {
        let baselineY = size.height * 0.34
        // The lagged camera height, subtracted from every sample. Using the exact terrain
        // height here instead would nail the skier to one pixel and flatten the ride.
        let referenceHeight = cameraHeightM

        let surface = CGMutablePath()
        let fill = CGMutablePath()
        fill.move(to: CGPoint(x: 0, y: 0))

        var screenX: CGFloat = 0
        var isFirstSample = true
        while screenX <= size.width {
            let worldX = distanceMetres
                + Double((screenX - size.width * skierScreenXFraction) / pointsPerMetre)
            let y = baselineY + CGFloat(terrain.height(at: worldX) - referenceHeight) * pointsPerMetre
            let point = CGPoint(x: screenX, y: y)

            if isFirstSample {
                surface.move(to: point)
                isFirstSample = false
            } else {
                surface.addLine(to: point)
            }
            fill.addLine(to: point)
            screenX += terrainSampleStep
        }

        fill.addLine(to: CGPoint(x: size.width, y: 0))
        fill.closeSubpath()

        slopeNode.path = fill
        slopeEdgeNode.path = surface
    }

    private func layoutSkier() {
        let baselineY = size.height * 0.34
        let screenX = size.width * skierScreenXFraction

        // Measured against the lagged camera, so the skier genuinely rises over crests and
        // drops into compressions instead of being pinned.
        let verticalOffset = CGFloat(skier.altitudeM - cameraHeightM) * pointsPerMetre

        skierNode.position = CGPoint(x: screenX, y: baselineY + verticalOffset)
        skierNode.zRotation = CGFloat(skier.rotation)
        // Tucking is readable in the silhouette before it is readable in the speed.
        skierNode.yScale = 1 - 0.32 * CGFloat(cues.tuckCompression)
        skierNode.alpha = skier.hasCrashed ? 0.55 : 1.0
    }

    private func layoutTrail() {
        guard trail.count > 1 else {
            trailNode.path = nil
            return
        }

        let baselineY = size.height * 0.34
        let screenX = size.width * skierScreenXFraction
        let path = CGMutablePath()

        for (index, point) in trail.enumerated() {
            let x = screenX - CGFloat(skier.distanceM - point.distance) * pointsPerMetre
            let y = baselineY + CGFloat(point.altitude - cameraHeightM) * pointsPerMetre
            let position = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }

        trailNode.path = path
    }
}
