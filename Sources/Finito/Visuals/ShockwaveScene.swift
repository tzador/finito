import SpriteKit

/// Expanding rings from the screen centre with a chromatic fringe, a flash and radial sparks.
final class ShockwaveScene: EffectScene {
    private struct Ring {
        let node: SKSpriteNode
        let delay: CGFloat
        let duration: CGFloat
        let maxScale: CGFloat
    }

    private struct Spark {
        let node: SKSpriteNode
        var position: CGPoint
        var velocity: CGVector
        var age: CGFloat = 0
        let life: CGFloat
    }

    private var rings: [Ring] = []
    private var sparks: [Spark] = []
    private var flash: SKSpriteNode?
    private var finished = false

    override var liveCount: Int { (finished ? 0 : 1) + sparks.count }

    override func fire() {
        let w = width, h = height
        let c = CGPoint(x: w / 2, y: h / 2)
        let reach = hypot(w, h) / 2
        let ringTexture = TextureFactory.ring(size: 256, thickness: 14)
        let dot = TextureFactory.glow(size: 32, hardness: 0.3)

        let fringe: [(NSColor, CGFloat)] = [(.white, 0), (NSColor.fromHex("#22b8cf"), 0.06), (NSColor.fromHex("#f06595"), 0.12), (.white, 0.35)]
        for (color, delay) in fringe {
            let node = SKSpriteNode(texture: ringTexture)
            node.size = CGSize(width: 256, height: 256)
            node.position = c
            node.color = color
            node.colorBlendFactor = 1
            node.blendMode = .add
            node.alpha = 0
            node.setScale(0.01)
            addChild(node)
            rings.append(Ring(node: node, delay: delay, duration: 1.3, maxScale: reach * 2.2 / 256))
        }

        let flash = SKSpriteNode(texture: TextureFactory.glow(size: 128))
        flash.size = CGSize(width: h * 0.6, height: h * 0.6)
        flash.position = c
        flash.blendMode = .add
        addChild(flash)
        self.flash = flash

        for _ in 0..<140 {
            let a = CGFloat.randomAngle
            let s = reach * .random(in: 0.6...1.6)
            let node = SKSpriteNode(texture: dot)
            let d = CGFloat.random(in: 4...9)
            node.size = CGSize(width: d, height: d)
            node.position = c
            node.color = .white
            node.colorBlendFactor = 1
            node.blendMode = .add
            addChild(node)
            sparks.append(Spark(node: node, position: c, velocity: CGVector(dx: cos(a) * s, dy: sin(a) * s), life: .random(in: 0.5...1.1)))
        }

        after(1.8) { [unowned self] in
            rings.forEach { $0.node.removeFromParent() }
            self.flash?.removeFromParent()
            finished = true
        }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        for r in rings {
            let p = (t - r.delay) / r.duration
            guard p >= 0 else { continue }
            let eased = easeOut(p)
            r.node.setScale(max(0.01, eased * r.maxScale))
            r.node.alpha = max(0, 1 - p) * 0.9
        }
        flash?.alpha = max(0, 1 - t / 0.35)
        flash?.setScale(1 + t * 2)

        for i in sparks.indices.reversed() {
            var s = sparks[i]
            s.age += dt
            if s.age >= s.life {
                s.node.removeFromParent()
                sparks.remove(at: i)
                continue
            }
            let damping = max(0, 1 - 2.2 * dt)
            s.velocity.dx *= damping
            s.velocity.dy *= damping
            s.position.x += s.velocity.dx * dt
            s.position.y += s.velocity.dy * dt
            s.node.position = s.position
            s.node.alpha = 1 - s.age / s.life
            sparks[i] = s
        }
    }
}
