import SpriteKit

/// A few dozen soft yellow-green lights wandering lazily and blinking.
final class FirefliesScene: EffectScene {
    private struct Fly {
        let node: SKSpriteNode
        var position: CGPoint
        var heading: CGFloat
        let speed: CGFloat
        let wobbleA: CGFloat, wobbleB: CGFloat
        let blinkPhase: CGFloat
        let blinkRate: CGFloat
        var age: CGFloat = 0
        let life: CGFloat
        let size: CGFloat
    }

    private var flies: [Fly] = []
    private var texture: SKTexture!
    private let colors = ["#ffe066", "#c0eb75", "#ffd43b", "#d8f5a2", "#fff3bf"].map(NSColor.fromHex)

    override var liveCount: Int { flies.count }

    override func didMove(to view: SKView) {
        guard texture == nil else { return }
        texture = TextureFactory.glow(size: 64)
    }

    override func fire() {
        let w = width, h = height
        emit(count: 70, over: 2.2) { [unowned self] in
            let size = CGFloat.random(in: 14...34)
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(width: size, height: size)
            node.color = colors.randomElement()!
            node.colorBlendFactor = 1
            node.blendMode = .add
            node.alpha = 0
            let position = CGPoint(x: .random(in: 0...w), y: .random(in: h * 0.05...h * 0.95))
            node.position = position
            addChild(node)
            flies.append(Fly(
                node: node, position: position, heading: .randomAngle,
                speed: .random(in: 25...70),
                wobbleA: .randomAngle, wobbleB: .randomAngle,
                blinkPhase: .randomAngle, blinkRate: .random(in: 0.6...1.6),
                life: .random(in: 4.5...7), size: size
            ))
        }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        for i in flies.indices.reversed() {
            var f = flies[i]
            f.age += dt
            if f.age >= f.life {
                f.node.removeFromParent()
                flies.remove(at: i)
                continue
            }
            // Wander: heading drifts with a sum of slow sines, and nudges back toward the screen.
            f.heading += (sin(t * 0.9 + f.wobbleA) * 1.6 + sin(t * 2.3 + f.wobbleB) * 0.9) * dt
            if f.position.x < 20 { f.heading = 0 } else if f.position.x > width - 20 { f.heading = .pi }
            if f.position.y < 20 { f.heading = .pi / 2 } else if f.position.y > height - 20 { f.heading = -.pi / 2 }
            f.position.x += cos(f.heading) * f.speed * dt
            f.position.y += sin(f.heading) * f.speed * dt

            let blink = pow(max(0, sin(t * f.blinkRate * 2 + f.blinkPhase)), 6)
            let env = lifeEnvelope(age: f.age, life: f.life, inSeconds: 1, outSeconds: 1.2)
            f.node.position = f.position
            f.node.alpha = env * (0.1 + 0.9 * blink)
            f.node.setScale(0.8 + 0.4 * blink)
            flies[i] = f
        }
    }
}
