import SpriteKit

/// Pink and red hearts floating up with a gentle pulse.
final class HeartsScene: EffectScene {
    private struct Heart {
        let node: SKSpriteNode
        var position: CGPoint
        let rise: CGFloat
        let phase: CGFloat
        let frequency: CGFloat
        let amplitude: CGFloat
        let size: CGFloat
        var age: CGFloat = 0
        let life: CGFloat
    }

    private var hearts: [Heart] = []
    private var texture: SKTexture!
    private let colors = ["#ff6b6b", "#f06595", "#e64980", "#fa5252", "#faa2c1", "#ff8787", "#f783ac", "#c2255c"].map(NSColor.fromHex)

    override var liveCount: Int { hearts.count }

    override func didMove(to view: SKView) {
        guard texture == nil else { return }
        texture = TextureFactory.shape(size: 64) { Paths.heart(in: $0.insetBy(dx: 4, dy: 4)) }
    }

    override func fire() {
        let w = width
        emit(count: 90, over: 3.2) { [unowned self] in
            let size = CGFloat.random(in: 18...64)
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(width: size, height: size)
            node.color = colors.randomElement()!
            node.colorBlendFactor = 1
            node.alpha = 0
            node.zPosition = size
            let position = CGPoint(x: .random(in: 0...w), y: -size)
            node.position = position
            addChild(node)
            hearts.append(Heart(
                node: node, position: position,
                rise: height * .random(in: 0.14...0.3) * (40 / size).squareRoot(),
                phase: .randomAngle, frequency: .random(in: 1...2.2), amplitude: .random(in: 15...50),
                size: size, life: .random(in: 3.5...6)
            ))
        }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        for i in hearts.indices.reversed() {
            var h = hearts[i]
            h.age += dt
            h.position.y += h.rise * dt
            h.position.x += cos(t * h.frequency + h.phase) * h.amplitude * dt
            if h.age >= h.life || h.position.y > height + h.size {
                h.node.removeFromParent()
                hearts.remove(at: i)
                continue
            }
            h.node.position = h.position
            h.node.alpha = lifeEnvelope(age: h.age, life: h.life, inSeconds: 0.4, outSeconds: 0.8) * 0.95
            h.node.setScale(1 + 0.12 * sin(t * 6 + h.phase))
            h.node.zRotation = sin(t * h.frequency + h.phase) * 0.25
            hearts[i] = h
        }
    }
}
