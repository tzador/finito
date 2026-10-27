import SpriteKit

/// Twinkling four-point sparkles drifting across the screen, with a few bright wand trails
/// sweeping through and leaving stardust behind them.
final class StarsScene: EffectScene {
    private struct Star {
        let node: SKSpriteNode
        var position: CGPoint
        var velocity: CGVector
        var age: CGFloat = 0
        let life: CGFloat
        let phase: CGFloat
        let frequency: CGFloat
        let baseSize: CGFloat
        let spin: CGFloat
    }

    private struct Wand {
        let node: SKSpriteNode
        var t: CGFloat = 0
        let duration: CGFloat
        let p0: CGPoint, p1: CGPoint, p2: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(
                x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
                y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
            )
        }
    }

    private var stars: [Star] = []
    private var wands: [Wand] = []
    private var sparkle: SKTexture!
    private var glow: SKTexture!
    private let colors = ["#fff3bf", "#ffe066", "#fcc419", "#ffffff", "#e5dbff", "#a5d8ff", "#ffd8a8"].map(NSColor.fromHex)

    override var liveCount: Int { stars.count + wands.count }

    override func didMove(to view: SKView) {
        guard sparkle == nil else { return }
        sparkle = TextureFactory.sparkle(size: 64)
        glow = TextureFactory.glow(size: 64)
    }

    override func fire() {
        let w = width, h = height
        // Three wand sweeps along curved paths, staggered.
        let paths: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: -40, y: h * 0.25), CGPoint(x: w * 0.5, y: h * 1.1), CGPoint(x: w + 40, y: h * 0.35)),
            (CGPoint(x: w + 40, y: h * 0.7), CGPoint(x: w * 0.4, y: -h * 0.1), CGPoint(x: -40, y: h * 0.6)),
            (CGPoint(x: w * 0.1, y: -40), CGPoint(x: w * 0.9, y: h * 0.5), CGPoint(x: w * 0.3, y: h + 40)),
        ]
        for (index, path) in paths.enumerated() {
            after(CGFloat(index) * 0.55) { [unowned self] in
                let node = SKSpriteNode(texture: glow)
                node.size = CGSize(width: 70, height: 70)
                node.color = .white
                node.colorBlendFactor = 1
                node.blendMode = .add
                node.zPosition = 200
                addChild(node)
                wands.append(Wand(node: node, duration: 1.6, p0: path.0, p1: path.1, p2: path.2))
            }
        }
        // Ambient stars popping in everywhere.
        emit(for: 3.0, rate: 55) { [unowned self] in
            addStar(at: CGPoint(x: .random(in: 0...w), y: .random(in: 0...h)), velocity: CGVector(dx: .random(in: -15...15), dy: .random(in: -25...10)), big: true)
        }
    }

    private func addStar(at position: CGPoint, velocity: CGVector, big: Bool) {
        let node = SKSpriteNode(texture: sparkle)
        let baseSize = big ? CGFloat.random(in: 18...46) : CGFloat.random(in: 8...22)
        node.size = CGSize(width: baseSize, height: baseSize)
        node.position = position
        node.color = colors.randomElement()!
        node.colorBlendFactor = 1
        node.blendMode = .add
        node.alpha = 0
        node.zPosition = .random(in: 0...100)
        addChild(node)
        stars.append(Star(
            node: node, position: position, velocity: velocity,
            life: big ? .random(in: 1.8...3.6) : .random(in: 0.8...1.8),
            phase: .randomAngle, frequency: .random(in: 5...11), baseSize: baseSize,
            spin: .random(in: -1.2...1.2)
        ))
    }

    override func step(dt: CGFloat) {
        for i in wands.indices.reversed() {
            var wand = wands[i]
            wand.t += dt / wand.duration
            let p = wand.point(at: min(1, wand.t))
            wand.node.position = p
            wand.node.alpha = lifeEnvelope(age: wand.t, life: 1, inSeconds: 0.1, outSeconds: 0.15)
            // Leave stardust behind the wand tip.
            for _ in 0..<3 where liveCount < maxLive {
                let jitter = CGPoint(x: p.x + .random(in: -14...14), y: p.y + .random(in: -14...14))
                addStar(at: jitter, velocity: CGVector(dx: .random(in: -40...40), dy: .random(in: -60...20)), big: false)
            }
            if wand.t >= 1 {
                wand.node.removeFromParent()
                wands.remove(at: i)
            } else {
                wands[i] = wand
            }
        }

        for i in stars.indices.reversed() {
            var s = stars[i]
            s.age += dt
            if s.age >= s.life {
                s.node.removeFromParent()
                stars.remove(at: i)
                continue
            }
            s.position.x += s.velocity.dx * dt
            s.position.y += s.velocity.dy * dt
            let twinkle = 0.55 + 0.45 * sin(elapsed * s.frequency + s.phase)
            let env = lifeEnvelope(age: s.age, life: s.life, inSeconds: 0.25, outSeconds: 0.6)
            s.node.position = s.position
            s.node.alpha = env * twinkle
            let scale = 0.7 + 0.3 * sin(elapsed * s.frequency * 0.5 + s.phase)
            s.node.setScale(scale)
            s.node.zRotation += s.spin * dt
            stars[i] = s
        }
    }
}
