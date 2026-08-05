import SpriteKit
import WhiteoutCore

/// Draws the skier from a `SkierPose`.
///
/// Holds no art, like everything else in the scene: the silhouette is strokes over a
/// skeleton and the two colours come from the weather-derived palette. Which means the
/// skier is legible at alpine noon and at midnight without a second asset existing.
final class SkierNode: SKNode {

    /// Standing height, in points.
    ///
    /// Roughly 7.5% of a landscape screen. The 20-point placeholder was closer to 5%, which
    /// is small enough that no amount of internal detail would have survived — the first
    /// thing a silhouette needs is somewhere to be.
    static let bodyHeightPoints: CGFloat = 30

    private let bodyHeight: CGFloat
    private let headNode: SKShapeNode
    private let layers: [StrokeLayer]

    /// One thickness class, drawn twice: a fat pass in the rim colour, then a thinner pass
    /// in the body colour on top of it.
    ///
    /// This is what produces a clean outline. Stroking a single path that already contains
    /// overlapping limbs would draw the seams *between* them too, and the skier reads as a
    /// jointed doll rather than as one shape.
    private struct StrokeLayer {
        let rim: SKShapeNode
        let body: SKShapeNode
        let segments: (SkierPose) -> [(RigPoint, RigPoint)]
    }

    init(palette: ScenePalette, bodyHeight: CGFloat = SkierNode.bodyHeightPoints) {
        self.bodyHeight = bodyHeight

        let bodyColour = palette.skierBody.uiColor
        let rimColour = palette.skierRim.uiColor
        // Deliberately thin. At 1.4 points the rim was wider on each side than the 2.5-point
        // limb it was outlining, so the figure read as a white stick drawing rather than as
        // a dark silhouette catching light. The floor keeps it from vanishing on a 1x screen
        // while staying a fraction of the thinnest thing it wraps.
        let rimWidth = max(0.75, bodyHeight * 0.028)

        func layer(
            width: Double,
            zPosition: CGFloat,
            segments: @escaping (SkierPose) -> [(RigPoint, RigPoint)]
        ) -> StrokeLayer {
            let strokeWidth = CGFloat(width) * bodyHeight

            let rim = SKShapeNode()
            rim.lineWidth = strokeWidth + rimWidth * 2
            rim.strokeColor = rimColour
            rim.fillColor = .clear
            rim.lineCap = .round
            rim.lineJoin = .round
            rim.zPosition = zPosition

            let body = SKShapeNode()
            body.lineWidth = strokeWidth
            body.strokeColor = bodyColour
            body.fillColor = .clear
            body.lineCap = .round
            body.lineJoin = .round
            body.zPosition = zPosition + 0.5

            return StrokeLayer(rim: rim, body: body, segments: segments)
        }

        // Equipment sits behind the skier, the body mass in front of it, limbs in front of
        // that — the ordering a viewer expects from a figure seen side-on.
        self.layers = [
            layer(width: SkierRig.Width.equipment, zPosition: 0) { pose in
                [(pose.skiTail, pose.skiTip), (pose.hand, pose.poleTip)]
            },
            layer(width: SkierRig.Width.core, zPosition: 2) { pose in
                [(pose.hip, pose.shoulder), (pose.hip, pose.knee)]
            },
            layer(width: SkierRig.Width.limb, zPosition: 4) { pose in
                [(pose.knee, pose.boot), (pose.shoulder, pose.elbow), (pose.elbow, pose.hand)]
            }
        ]

        // The head is fixed geometry, so it is built once and only ever repositioned. It is
        // the one part that must not be a stroke: a filled disc with its own rim is what
        // stops it dissolving into the shoulders at this size.
        self.headNode = SKShapeNode(circleOfRadius: CGFloat(SkierRig.headRadius) * bodyHeight)
        self.headNode.fillColor = bodyColour
        self.headNode.strokeColor = rimColour
        self.headNode.lineWidth = rimWidth
        self.headNode.zPosition = 6

        super.init()

        for stroke in layers {
            addChild(stroke.rim)
            addChild(stroke.body)
        }
        addChild(headNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Where the skis meet the snow, in this node's coordinates.
    ///
    /// The spray emitter needs this: snow is thrown from the edges, and an emitter parked on
    /// the body centre puts the plume at the skier's waist.
    func contactPoint(for pose: SkierPose) -> CGPoint {
        convert(point(pose.boot), to: parent ?? self)
    }

    func apply(_ pose: SkierPose) {
        for stroke in layers {
            let path = CGMutablePath()
            for (start, end) in stroke.segments(pose) {
                path.move(to: point(start))
                path.addLine(to: point(end))
            }
            // Both passes share one path, so the outline can never drift out of register
            // with the body it outlines.
            stroke.rim.path = path
            stroke.body.path = path
        }
        headNode.position = point(pose.head)
    }

    private func point(_ rigPoint: RigPoint) -> CGPoint {
        CGPoint(x: CGFloat(rigPoint.x) * bodyHeight, y: CGFloat(rigPoint.y) * bodyHeight)
    }
}
