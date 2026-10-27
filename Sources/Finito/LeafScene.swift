import SpriteKit
import ImageIO

/// Autumn leaves drifting across the screen, rendered with SpriteKit sprites cut from the
/// embedded leaf atlas.
///
/// A leaf does not fall straight. It glides sideways on a tilt, stalls at the end of the glide,
/// drops a little faster while it swings back, and banks into the new direction. Most leaves
/// only rock about their long axis; some tumble right over. A slowly changing wind field, with
/// a gust at the start of some shows, pushes the whole cloud around. Far leaves are smaller,
/// slower and dimmer than near ones, which gives the cloud some depth.
///
/// The show itself (launch pattern, wind, density, duration) is composed from a seed, so every
/// launch looks a little different.
final class LeafScene: SKScene {
    var onIdle: (() -> Void)?
    var isIdle: Bool { leaves.isEmpty && spawners.isEmpty }

    private struct Leaf {
        let node: SKSpriteNode
        var position: CGPoint
        var velocity: CGVector
        let depth: CGFloat             // 0.55 (far: small, slow, dim) ... 1 (near)
        let size: CGFloat              // long axis in points
        let descent: CGFloat           // steady fall speed, points per second
        let response: CGFloat          // how quickly velocity relaxes toward the glide, per second
        let glideSpeed: CGFloat        // horizontal speed at the middle of a glide
        let glideFrequency: CGFloat    // radians per second
        let glidePhase: CGFloat
        var rotation: CGFloat
        let spin: CGFloat              // steady rotation, radians per second
        let bank: CGFloat              // how far the leaf tilts into its glide, radians
        var flip: CGFloat
        let flipSpeed: CGFloat
        let flipRange: CGFloat         // rocking amplitude in radians, or .infinity for tumblers
        var age: CGFloat = 0
        let life: CGFloat
    }

    /// Emits leaves for a duration at a rate.
    private struct Spawner {
        var delay: CGFloat = 0          // seconds before it starts
        var remaining: CGFloat          // seconds left once started
        var rate: CGFloat               // leaves per second
        var accumulator: CGFloat = 0
        let make: () -> Leaf
    }

    private enum Pattern: CaseIterable { case fall, gust, swirl, everything }

    /// What this launch looks like, decided once from the seed.
    private struct Design {
        let pattern: Pattern
        let gustFromLeft: Bool
        let windStrength: CGFloat
        let density: CGFloat
        let duration: CGFloat           // seconds of steady fall from the top
    }

    private let design: Design
    private var leaves: [Leaf] = []
    private var spawners: [Spawner] = []
    private var textures: [(texture: SKTexture, aspect: CGFloat)] = []
    private var lastTime: TimeInterval?
    private var elapsed: CGFloat = 0
    private var notifiedIdle = true

    private let maxLeaves = 700

    init(size: CGSize, seed: UInt32) {
        var rng = SeededRandom(seed: seed &+ 0x5EED)
        let patterns = Pattern.allCases
        design = Design(
            pattern: patterns[Int(rng.nextUnit() * Float(patterns.count) * 0.999)],
            gustFromLeft: rng.nextUnit() < 0.5,
            windStrength: CGFloat(0.4 + rng.nextUnit() * 0.9),
            density: CGFloat(0.75 + rng.nextUnit() * 0.6),
            duration: CGFloat(2.2 + rng.nextUnit() * 1.8)
        )
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        guard textures.isEmpty, let atlas = LeafScene.loadAtlas() else { return }
        let w = CGFloat(LeafAtlas.width), h = CGFloat(LeafAtlas.height)
        for i in stride(from: 0, to: LeafAtlas.rects.count, by: 4) {
            let r = LeafAtlas.rects[i..<i + 4].map(CGFloat.init)
            let rect = CGRect(x: r[0] / w, y: r[1] / h, width: r[2] / w, height: r[3] / h)
            textures.append((SKTexture(rect: rect, in: atlas), r[2] / r[3]))
        }
    }

    private static func loadAtlas() -> SKTexture? {
        guard let data = Data(base64Encoded: LeafAtlas.png),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        texture.usesMipmaps = true
        return texture
    }

    // MARK: - Firing

    func burst() {
        notifiedIdle = false
        let w = size.width
        let density = design.density

        func fall(duration: CGFloat, rate: CGFloat, delay: CGFloat = 0) {
            spawners.append(Spawner(delay: delay, remaining: duration, rate: rate * density) { [unowned self] in
                self.fallingLeaf()
            })
        }
        func gust(fromLeft: Bool, duration: CGFloat = 1.4, rate: CGFloat = 110) {
            spawners.append(Spawner(remaining: duration, rate: rate * density) { [unowned self] in
                self.gustLeaf(fromLeft: fromLeft)
            })
        }
        func swirl(at origin: CGPoint, angle: CGFloat, delay: CGFloat = 0) {
            spawners.append(Spawner(delay: delay, remaining: 0.3, rate: 320 * density) { [unowned self] in
                self.swirlLeaf(origin: origin, angle: angle, power: 1)
            })
            spawners.append(Spawner(delay: delay, remaining: 1.0, rate: 50 * density) { [unowned self] in
                self.swirlLeaf(origin: origin, angle: angle, power: 0.75)
            })
        }

        switch design.pattern {
        case .fall:
            // A steady shower from above, nothing else.
            fall(duration: design.duration + 0.5, rate: 60)
        case .gust:
            // A gust sweeps a cloud of leaves in from one side, and a few more keep falling after.
            gust(fromLeft: design.gustFromLeft)
            fall(duration: design.duration * 0.7, rate: 30, delay: 0.5)
        case .swirl:
            // Leaves kicked up from both bottom corners, whirling up before they settle.
            swirl(at: CGPoint(x: w * 0.04, y: -20), angle: .pi / 2 - 0.55)
            swirl(at: CGPoint(x: w * 0.96, y: -20), angle: .pi / 2 + 0.55, delay: 0.15)
            fall(duration: design.duration * 0.6, rate: 35, delay: 0.3)
        case .everything:
            gust(fromLeft: design.gustFromLeft, duration: 1.1, rate: 90)
            let corner = design.gustFromLeft ? CGPoint(x: w * 0.96, y: -20) : CGPoint(x: w * 0.04, y: -20)
            swirl(at: corner, angle: design.gustFromLeft ? .pi / 2 + 0.55 : .pi / 2 - 0.55, delay: 0.4)
            fall(duration: design.duration, rate: 45, delay: 0.3)
        }
    }

    private func fallingLeaf() -> Leaf {
        let h = size.height
        let depth = randomDepth()
        return makeLeaf(
            depth: depth,
            position: CGPoint(x: .random(in: -size.width * 0.05...size.width * 1.05), y: h + h * 0.08),
            velocity: CGVector(dx: wind(at: h, depth: depth), dy: -h * .random(in: 0.1...0.25) * depth)
        )
    }

    private func gustLeaf(fromLeft: Bool) -> Leaf {
        let w = size.width, h = size.height
        let depth = randomDepth()
        let speed = h * CGFloat.random(in: 1.4...2.4) * depth
        let rise = h * CGFloat.random(in: -0.1...0.45) * depth
        return makeLeaf(
            depth: depth,
            position: CGPoint(x: fromLeft ? -h * 0.1 : w + h * 0.1, y: .random(in: h * 0.1...h * 1.05)),
            velocity: CGVector(dx: fromLeft ? speed : -speed, dy: rise)
        )
    }

    private func swirlLeaf(origin: CGPoint, angle: CGFloat, power: CGFloat) -> Leaf {
        let h = size.height
        let depth = randomDepth()
        let spread = CGFloat.random(in: -0.5...0.5)
        let theta = angle + spread * abs(spread) * 2.2
        let speed = h * CGFloat.random(in: 1.6...2.9) * power * depth
        return makeLeaf(
            depth: depth,
            position: CGPoint(x: origin.x + .random(in: -30...30), y: origin.y),
            velocity: CGVector(dx: cos(theta) * speed, dy: sin(theta) * speed)
        )
    }

    private func randomDepth() -> CGFloat {
        // Skewed toward near leaves so the big, bright ones dominate.
        let u = CGFloat.random(in: 0..<1)
        return 0.55 + 0.45 * u.squareRoot()
    }

    private func makeLeaf(depth: CGFloat, position: CGPoint, velocity: CGVector) -> Leaf {
        let h = size.height
        let (texture, aspect) = textures.randomElement()!
        let longAxis = h * CGFloat.random(in: 0.042...0.07) * depth
        let node = SKSpriteNode(texture: texture)
        node.size = aspect >= 1
            ? CGSize(width: longAxis, height: longAxis / aspect)
            : CGSize(width: longAxis * aspect, height: longAxis)
        node.position = position
        node.zPosition = depth * 100
        node.color = .black
        node.colorBlendFactor = 0
        node.alpha = 0.7 + 0.3 * depth
        addChild(node)

        let tumbles = CGFloat.random(in: 0..<1) < 0.22
        return Leaf(
            node: node,
            position: position,
            velocity: velocity,
            depth: depth,
            size: longAxis,
            descent: h * CGFloat.random(in: 0.2...0.32) * depth,
            response: .random(in: 1.1...2.4),
            glideSpeed: h * CGFloat.random(in: 0.12...0.32) * depth,
            glideFrequency: .random(in: 1.5...3.2),
            glidePhase: .random(in: 0...(2 * .pi)),
            rotation: .random(in: 0...(2 * .pi)),
            spin: .random(in: -0.9...0.9),
            bank: .random(in: 0.25...0.6),
            flip: .random(in: 0...(2 * .pi)),
            flipSpeed: tumbles ? .random(in: 3...7) * (Bool.random() ? 1 : -1) : .random(in: 0.8...2.2),
            flipRange: tumbles ? .infinity : .random(in: 0.35...1.1),
            life: 14
        )
    }

    // MARK: - Simulation

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(min(1.0 / 30.0, lastTime.map { currentTime - $0 } ?? 1.0 / 60.0))
        lastTime = currentTime
        elapsed += dt

        spawn(dt: dt)
        step(dt: dt)

        if isIdle, !notifiedIdle {
            notifiedIdle = true
            onIdle?()
        }
    }

    private func spawn(dt: CGFloat) {
        for i in spawners.indices.reversed() {
            if spawners[i].delay > 0 {
                spawners[i].delay -= dt
                continue
            }
            spawners[i].remaining -= dt
            spawners[i].accumulator += spawners[i].rate * dt
            while spawners[i].accumulator >= 1, leaves.count < maxLeaves {
                spawners[i].accumulator -= 1
                leaves.append(spawners[i].make())
            }
            if spawners[i].remaining <= 0 { spawners.remove(at: i) }
        }
    }

    /// Horizontal wind at a height, in points per second: a slowly wandering breeze plus, for
    /// gust shows, a strong push from the gust side that dies away over the first seconds.
    private func wind(at y: CGFloat, depth: CGFloat) -> CGFloat {
        let h = size.height, t = elapsed
        let breeze = (sin(t * 0.5) * 0.5 + sin(t * 1.3 + 1.3) * 0.3 + sin(t * 2.9 + 0.4) * 0.15) * design.windStrength
        var wind = breeze * h * 0.14
        if design.pattern == .gust || design.pattern == .everything {
            let push = h * 0.7 * design.windStrength * exp(-t / 1.7)
            wind += design.gustFromLeft ? push : -push
        }
        return wind * (0.6 + 0.6 * min(1, max(0, y / h))) * depth
    }

    private func step(dt: CGFloat) {
        let h = size.height, w = size.width
        let t = elapsed

        for i in leaves.indices.reversed() {
            var leaf = leaves[i]
            leaf.age += dt

            // Glide: slide sideways, stall at the turn, drop faster while swinging back.
            let glide = cos(t * leaf.glideFrequency + leaf.glidePhase)
            let stall = 1 - abs(glide)
            let targetX = leaf.glideSpeed * glide + wind(at: leaf.position.y, depth: leaf.depth)
            let targetY = -leaf.descent * (0.7 + 0.6 * stall)
            let k = min(1, leaf.response * dt)
            leaf.velocity.dx += (targetX - leaf.velocity.dx) * k
            leaf.velocity.dy += (targetY - leaf.velocity.dy) * k
            leaf.position.x += leaf.velocity.dx * dt
            leaf.position.y += leaf.velocity.dy * dt

            // Tumble while moving fast (gusts, swirls), settle into a lazy rock while drifting.
            let speedFactor = min(1, hypot(leaf.velocity.dx, leaf.velocity.dy) / (h * 0.9))
            leaf.rotation += leaf.spin * (0.5 + 3.5 * speedFactor) * dt
            leaf.flip += leaf.flipSpeed * (0.6 + 2.4 * speedFactor) * dt

            let fade = min(1, (leaf.life - leaf.age) / 1.2)
            let margin = leaf.size * 2
            let dead = leaf.age >= leaf.life || leaf.position.y < -margin
                || leaf.position.x < -w * 0.15 - margin || leaf.position.x > w * 1.15 + margin

            if dead {
                leaf.node.removeFromParent()
                leaves.remove(at: i)
                continue
            }

            let node = leaf.node
            node.position = leaf.position
            node.zRotation = leaf.rotation + leaf.bank * glide
            let flipAngle = leaf.flipRange.isFinite ? leaf.flipRange * sin(leaf.flip) : leaf.flip
            let facing = abs(cos(flipAngle))
            node.xScale = max(0.1, facing)
            node.yScale = 1
            // Edge-on leaves catch less light; far leaves sit a little in the haze.
            node.colorBlendFactor = 0.4 * (1 - facing) + 0.2 * (1 - leaf.depth)
            node.alpha = (0.7 + 0.3 * leaf.depth) * fade
            leaves[i] = leaf
        }
    }
}
