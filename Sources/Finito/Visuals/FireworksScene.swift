import SpriteKit

/// Rockets climb from the bottom with a spark trail, then burst into chrysanthemums, willows,
/// rings and two-tone peonies.
final class FireworksScene: EffectScene {
    private enum Style: CaseIterable { case chrysanthemum, willow, ring, peony }

    private struct Rocket {
        let node: SKSpriteNode
        var position: CGPoint
        var velocity: CGVector
        var fuse: CGFloat
        let color: NSColor
        let style: Style
    }

    private struct Spark {
        let node: SKSpriteNode
        var position: CGPoint
        var velocity: CGVector
        var age: CGFloat = 0
        let life: CGFloat
        let gravity: CGFloat
        let drag: CGFloat
        let flicker: Bool
    }

    private var rockets: [Rocket] = []
    private var sparks: [Spark] = []
    private var dot: SKTexture!
    private let colors = ["#ff6b6b", "#fcc419", "#51cf66", "#339af0", "#cc5de8", "#ff922b", "#22b8cf", "#f06595", "#ffffff"].map(NSColor.fromHex)

    override var liveCount: Int { rockets.count + sparks.count }
    override var maxLive: Int { 2200 }

    override func didMove(to view: SKView) {
        guard dot == nil else { return }
        dot = TextureFactory.glow(size: 32, hardness: 0.3)
    }

    override func fire() {
        let w = width, h = height
        let launches = 7
        for i in 0..<launches {
            after(CGFloat(i) * 0.42 + .random(in: 0...0.15)) { [unowned self] in
                let x = w * .random(in: 0.15...0.85)
                let node = SKSpriteNode(texture: dot)
                node.size = CGSize(width: 10, height: 10)
                node.position = CGPoint(x: x, y: -10)
                node.color = .white
                node.colorBlendFactor = 0.6
                node.blendMode = .add
                addChild(node)
                let apexFraction = CGFloat.random(in: 0.55...0.9)
                let speed = h * (2.6 * apexFraction).squareRoot()
                rockets.append(Rocket(
                    node: node, position: node.position,
                    velocity: CGVector(dx: .random(in: -w * 0.04...w * 0.04), dy: speed),
                    fuse: .random(in: 0.9...1.3),
                    color: colors.randomElement()!,
                    style: Style.allCases.randomElement()!
                ))
            }
        }
    }

    private func addSpark(at p: CGPoint, velocity: CGVector, color: NSColor, size: CGFloat, life: CGFloat, gravity: CGFloat, drag: CGFloat, flicker: Bool) {
        let node = SKSpriteNode(texture: dot)
        node.size = CGSize(width: size, height: size)
        node.position = p
        node.color = color
        node.colorBlendFactor = 1
        node.blendMode = .add
        addChild(node)
        sparks.append(Spark(node: node, position: p, velocity: velocity, life: life, gravity: gravity, drag: drag, flicker: flicker))
    }

    private func explode(_ r: Rocket) {
        let h = height
        let second = colors.randomElement()!
        switch r.style {
        case .chrysanthemum:
            for _ in 0..<140 {
                let a = CGFloat.randomAngle
                let s = h * .random(in: 0.25...0.75)
                addSpark(at: r.position, velocity: CGVector(dx: cos(a) * s, dy: sin(a) * s), color: r.color, size: .random(in: 5...9), life: .random(in: 1.2...2.0), gravity: 0.35, drag: 1.6, flicker: true)
            }
        case .willow:
            for _ in 0..<160 {
                let a = CGFloat.randomAngle
                let s = h * .random(in: 0.15...0.5)
                addSpark(at: r.position, velocity: CGVector(dx: cos(a) * s, dy: sin(a) * s), color: NSColor.fromHex("#ffd43b"), size: .random(in: 4...7), life: .random(in: 2.4...3.4), gravity: 0.55, drag: 0.9, flicker: false)
            }
        case .ring:
            let tilt = CGFloat.random(in: 0.5...1)
            let base = h * .random(in: 0.45...0.6)
            for i in 0..<110 {
                let a = CGFloat(i) / 110 * 2 * .pi
                addSpark(at: r.position, velocity: CGVector(dx: cos(a) * base, dy: sin(a) * base * tilt), color: r.color, size: 7, life: .random(in: 1.3...1.7), gravity: 0.25, drag: 1.7, flicker: false)
            }
        case .peony:
            for i in 0..<180 {
                let a = CGFloat.randomAngle
                let inner = i % 3 == 0
                let s = h * (inner ? .random(in: 0.12...0.3) : .random(in: 0.4...0.7))
                addSpark(at: r.position, velocity: CGVector(dx: cos(a) * s, dy: sin(a) * s), color: inner ? second : r.color, size: .random(in: 5...8), life: .random(in: 1.0...1.9), gravity: 0.3, drag: 1.5, flicker: true)
            }
        }
        // Flash at the burst point.
        addSpark(at: r.position, velocity: .zero, color: .white, size: h * 0.12, life: 0.18, gravity: 0, drag: 0, flicker: false)
    }

    override func step(dt: CGFloat) {
        let g = height * 1.3
        for i in rockets.indices.reversed() {
            var r = rockets[i]
            r.fuse -= dt
            r.velocity.dy -= g * dt
            r.position.x += r.velocity.dx * dt
            r.position.y += r.velocity.dy * dt
            r.node.position = r.position
            // Trail.
            for _ in 0..<2 where liveCount < maxLive {
                addSpark(at: r.position, velocity: CGVector(dx: .random(in: -30...30), dy: -r.velocity.dy * 0.15), color: NSColor.fromHex("#ffa94d"), size: .random(in: 3...6), life: .random(in: 0.25...0.5), gravity: 0.2, drag: 2, flicker: false)
            }
            if r.fuse <= 0 || r.velocity.dy < height * 0.2 {
                r.node.removeFromParent()
                rockets.remove(at: i)
                explode(r)
            } else {
                rockets[i] = r
            }
        }

        for i in sparks.indices.reversed() {
            var s = sparks[i]
            s.age += dt
            if s.age >= s.life || s.position.y < -20 {
                s.node.removeFromParent()
                sparks.remove(at: i)
                continue
            }
            s.velocity.dy -= g * s.gravity * dt
            let damping = max(0, 1 - s.drag * dt)
            s.velocity.dx *= damping
            s.velocity.dy *= damping
            s.position.x += s.velocity.dx * dt
            s.position.y += s.velocity.dy * dt
            s.node.position = s.position
            let fade = 1 - s.age / s.life
            let flicker = s.flicker && s.age > s.life * 0.5 ? (Bool.random() ? 1.0 : 0.3) : 1.0
            s.node.alpha = fade * flicker
            sparks[i] = s
        }
    }
}
