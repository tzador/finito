import SpriteKit

/// A seven-band rainbow drawn progressively from one bottom edge to the other, then fading.
final class RainbowScene: EffectScene {
    private var bands: [SKShapeNode] = []
    private var tips: [SKSpriteNode] = []
    private var sparks: [(node: SKSpriteNode, velocity: CGVector, age: CGFloat, life: CGFloat)] = []
    private var finished = false
    private var glow: SKTexture!

    private let drawDuration: CGFloat = 2.0
    private let hold: CGFloat = 1.3
    private let fade: CGFloat = 1.1

    private let colors = ["#fa5252", "#fd7e14", "#fab005", "#40c057", "#228be6", "#4c6ef5", "#be4bdb"].map(NSColor.fromHex)

    override var liveCount: Int { finished ? 0 : 1 }

    override func didMove(to view: SKView) {
        guard glow == nil else { return }
        glow = TextureFactory.glow(size: 64)
    }

    private var center: CGPoint { CGPoint(x: width / 2, y: -height * 0.08) }
    private var outerRadius: CGFloat { min(width * 0.47, height * 0.9) }
    private var bandWidth: CGFloat { outerRadius * 0.055 }

    override func fire() {
        for color in colors {
            let band = SKShapeNode()
            band.strokeColor = color
            band.lineWidth = bandWidth + 1
            band.lineCap = .round
            band.alpha = 0.9
            band.isAntialiased = true
            addChild(band)
            bands.append(band)

            let tip = SKSpriteNode(texture: glow)
            tip.size = CGSize(width: bandWidth * 2.2, height: bandWidth * 2.2)
            tip.color = .white
            tip.colorBlendFactor = 1
            tip.blendMode = .add
            tip.zPosition = 10
            addChild(tip)
            tips.append(tip)
        }
        after(drawDuration + hold + fade) { [unowned self] in
            bands.forEach { $0.removeFromParent() }
            tips.forEach { $0.removeFromParent() }
            finished = true
        }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        let progress = easeOut(t / drawDuration)
        let sweep = CGFloat.pi * progress
        let c = center

        for (i, band) in bands.enumerated() {
            let radius = outerRadius - bandWidth * (CGFloat(i) + 0.5)
            let path = CGMutablePath()
            path.addArc(center: c, radius: radius, startAngle: .pi, endAngle: .pi - sweep, clockwise: true)
            band.path = path

            let tipPoint = CGPoint(x: c.x + radius * cos(.pi - sweep), y: c.y + radius * sin(.pi - sweep))
            tips[i].position = tipPoint
            tips[i].alpha = progress < 1 ? 1 : max(0, 1 - (t - drawDuration) / 0.4)
            if progress < 1, liveCount < maxLive, Bool.random() {
                let node = SKSpriteNode(texture: glow)
                let d = CGFloat.random(in: 4...10)
                node.size = CGSize(width: d, height: d)
                node.position = tipPoint
                node.color = colors[i]
                node.colorBlendFactor = 0.6
                node.blendMode = .add
                addChild(node)
                sparks.append((node, CGVector(dx: .random(in: -80...80), dy: .random(in: -40...120)), 0, .random(in: 0.4...0.9)))
            }
        }

        if t > drawDuration + hold {
            let alpha = max(0, 1 - (t - drawDuration - hold) / fade)
            bands.forEach { $0.alpha = 0.9 * alpha }
        }

        for i in sparks.indices.reversed() {
            sparks[i].age += dt
            if sparks[i].age >= sparks[i].life {
                sparks[i].node.removeFromParent()
                sparks.remove(at: i)
                continue
            }
            sparks[i].velocity.dy -= height * 0.6 * dt
            sparks[i].node.position.x += sparks[i].velocity.dx * dt
            sparks[i].node.position.y += sparks[i].velocity.dy * dt
            sparks[i].node.alpha = 1 - sparks[i].age / sparks[i].life
        }
    }
}
