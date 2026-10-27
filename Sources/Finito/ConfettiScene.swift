import SpriteKit

/// A hand-rolled confetti simulation rendered with SpriteKit sprites.
///
/// Each piece of confetti is a flat shape with air drag that depends on how it is oriented,
/// a tumbling 3D flip (faked with a local-axis scale and darkening when edge-on),
/// side-to-side flutter and a slowly changing wind field. Streamers are long ribbons that
/// twist and drift more slowly; glitter is tiny glowing dust that twinkles.
///
/// The show itself (launch pattern, colour theme, how many streamers and how much glitter)
/// is composed from a seed, so every launch looks a little different.
final class ConfettiScene: SKScene {
    var onIdle: (() -> Void)?
    var isIdle: Bool { particles.isEmpty && spawners.isEmpty }

    private enum Kind { case piece, streamer, glitter }

    private struct Particle {
        let node: SKSpriteNode
        let kind: Kind
        var position: CGPoint
        var velocity: CGVector
        var drag: CGFloat
        var rotation: CGFloat
        var rotationSpeed: CGFloat
        var flip: CGFloat
        var flipSpeed: CGFloat
        var flutterPhase: CGFloat
        var flutterFrequency: CGFloat
        var flutterAmplitude: CGFloat
        var size: CGFloat
        var age: CGFloat = 0
        var life: CGFloat
    }

    /// Emits particles for a duration at a rate.
    private struct Spawner {
        var delay: CGFloat = 0          // seconds before it starts
        var remaining: CGFloat          // seconds left once started
        var rate: CGFloat               // particles per second
        var accumulator: CGFloat = 0
        let make: () -> Particle
    }

    private enum Pattern: CaseIterable { case corners, fountain, sides, shower, everything }

    /// What this launch looks like, decided once from the seed.
    private struct Design {
        let pattern: Pattern
        let colors: [NSColor]
        let streamerShare: CGFloat      // fraction of cannon pieces that are streamers
        let glitterShare: CGFloat       // fraction of pieces that are glitter
        let windStrength: CGFloat
        let rainDuration: CGFloat
    }

    private let design: Design
    private var particles: [Particle] = []
    private var spawners: [Spawner] = []
    private var pieceTextures: [SKTexture] = []
    private var streamerTextures: [SKTexture] = []
    private var glitterTexture: SKTexture?
    private var lastTime: TimeInterval?
    private var elapsed: CGFloat = 0
    private var notifiedIdle = true

    private var gravity: CGFloat { size.height * 2.2 }
    private let maxParticles = 1600

    init(size: CGSize, seed: UInt32) {
        var rng = SeededRandom(seed: seed &+ 0x5EED)
        let patterns = Pattern.allCases
        design = Design(
            pattern: patterns[Int(rng.nextUnit() * Float(patterns.count) * 0.999)],
            colors: OpenColor.themes[Int(rng.nextUnit() * Float(OpenColor.themes.count) * 0.999)],
            streamerShare: rng.nextUnit() < 0.3 ? 0 : CGFloat(0.04 + rng.nextUnit() * 0.08),
            glitterShare: rng.nextUnit() < 0.35 ? 0 : CGFloat(0.1 + rng.nextUnit() * 0.2),
            windStrength: CGFloat(0.5 + rng.nextUnit()),
            rainDuration: CGFloat(1.4 + rng.nextUnit() * 1.2)
        )
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        guard pieceTextures.isEmpty else { return }
        for shape in ConfettiShape.allCases {
            for color in design.colors {
                if let image = shape.image(color: color, size: 32) {
                    let texture = SKTexture(cgImage: image)
                    texture.filteringMode = .linear
                    pieceTextures.append(texture)
                }
            }
        }
        for color in design.colors {
            if let image = ConfettiShape.streamerImage(color: color, width: 6, height: 44) {
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = .linear
                streamerTextures.append(texture)
            }
        }
        if let image = ConfettiShape.glowImage(size: 16) {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .linear
            glitterTexture = texture
        }
    }

    // MARK: - Firing

    func burst() {
        notifiedIdle = false
        let w = size.width, h = size.height

        func cannon(at origin: CGPoint, angle: CGFloat, power: CGFloat = 1, pop: CGFloat = 0.18, stream: CGFloat = 1.1, delay: CGFloat = 0) {
            spawners.append(Spawner(delay: delay, remaining: pop, rate: 1500 * power) { [unowned self] in
                self.cannonParticle(origin: origin, angle: angle, power: power)
            })
            spawners.append(Spawner(delay: delay, remaining: stream, rate: 220 * power) { [unowned self] in
                self.cannonParticle(origin: origin, angle: angle, power: power * 0.8)
            })
        }
        func rain(duration: CGFloat, rate: CGFloat = 130) {
            spawners.append(Spawner(remaining: duration, rate: rate) { [unowned self] in
                self.rainParticle()
            })
        }

        switch design.pattern {
        case .corners:
            // Two party poppers in the bottom corners: a hard pop, then a short stream.
            cannon(at: CGPoint(x: w * 0.03, y: -10), angle: .pi / 2 - 0.62)
            cannon(at: CGPoint(x: w * 0.97, y: -10), angle: .pi / 2 + 0.62)
            rain(duration: design.rainDuration)
        case .fountain:
            // One big fountain from the bottom centre, with a second pulse.
            cannon(at: CGPoint(x: w * 0.5, y: -10), angle: .pi / 2, power: 1.15, pop: 0.22, stream: 1.0)
            cannon(at: CGPoint(x: w * 0.5, y: -10), angle: .pi / 2, power: 0.9, pop: 0.15, stream: 0.5, delay: 0.9)
            rain(duration: design.rainDuration * 0.8, rate: 90)
        case .sides:
            // Blasters from both side edges at mid height, aimed up and inward.
            cannon(at: CGPoint(x: -10, y: h * 0.45), angle: 0.55, power: 0.95)
            cannon(at: CGPoint(x: w + 10, y: h * 0.45), angle: .pi - 0.55, power: 0.95)
            rain(duration: design.rainDuration * 0.7, rate: 80)
        case .shower:
            // Nothing but a long, heavy shower from above.
            rain(duration: design.rainDuration + 1.6, rate: 420)
        case .everything:
            cannon(at: CGPoint(x: w * 0.03, y: -10), angle: .pi / 2 - 0.62, power: 0.85)
            cannon(at: CGPoint(x: w * 0.97, y: -10), angle: .pi / 2 + 0.62, power: 0.85)
            cannon(at: CGPoint(x: w * 0.5, y: -10), angle: .pi / 2, power: 0.9, pop: 0.16)
            rain(duration: design.rainDuration, rate: 160)
        }
    }

    private func cannonParticle(origin: CGPoint, angle: CGFloat, power: CGFloat) -> Particle {
        let h = size.height
        let spread = CGFloat.random(in: -0.5...0.5)
        let theta = angle + spread * abs(spread) * 2.4 // denser in the middle of the cone, up to ±0.6 rad
        let speed = h * CGFloat.random(in: 3.5...7.5) * power
        let kind = pickKind(allowStreamers: true)
        return makeParticle(
            kind: kind,
            position: CGPoint(x: origin.x + .random(in: -20...20), y: origin.y),
            velocity: CGVector(dx: cos(theta) * speed, dy: sin(theta) * speed),
            life: kind == .streamer ? .random(in: 4.5...6.5) : .random(in: 3.5...5.5)
        )
    }

    private func rainParticle() -> Particle {
        let h = size.height
        return makeParticle(
            kind: pickKind(allowStreamers: false),
            position: CGPoint(x: .random(in: -20...(size.width + 20)), y: h + 30),
            velocity: CGVector(dx: .random(in: -h * 0.05...h * 0.05), dy: -h * .random(in: 0.15...0.4)),
            life: .random(in: 4...6)
        )
    }

    private func pickKind(allowStreamers: Bool) -> Kind {
        let roll = CGFloat.random(in: 0..<1)
        if allowStreamers, roll < design.streamerShare, !streamerTextures.isEmpty { return .streamer }
        if roll < design.streamerShare + design.glitterShare, glitterTexture != nil { return .glitter }
        return .piece
    }

    private func makeParticle(kind: Kind, position: CGPoint, velocity: CGVector, life: CGFloat) -> Particle {
        let h = size.height
        let node: SKSpriteNode
        let pieceSize: CGFloat
        var terminal: CGFloat
        var rotationSpeed = CGFloat.random(in: -6...6)
        var flipSpeed = CGFloat.random(in: 4...11) * (Bool.random() ? 1 : -1)
        var flutterAmplitude = h * CGFloat.random(in: 0.08...0.2)

        switch kind {
        case .piece:
            pieceSize = .random(in: 9...22)
            node = SKSpriteNode(texture: pieceTextures.randomElement())
            node.size = CGSize(width: pieceSize, height: pieceSize)
            // Lighter (smaller) pieces have a lower terminal velocity: terminal = gravity / drag.
            terminal = h * CGFloat.random(in: 0.22...0.5) * (pieceSize / 16).squareRoot()
        case .streamer:
            pieceSize = .random(in: 36...70)
            node = SKSpriteNode(texture: streamerTextures.randomElement())
            node.size = CGSize(width: pieceSize * 0.14, height: pieceSize)
            terminal = h * CGFloat.random(in: 0.14...0.26)
            rotationSpeed = .random(in: -2.5...2.5)
            flipSpeed = .random(in: 2...5) * (Bool.random() ? 1 : -1)
            flutterAmplitude = h * CGFloat.random(in: 0.15...0.3)
        case .glitter:
            pieceSize = .random(in: 3...6)
            node = SKSpriteNode(texture: glitterTexture)
            node.size = CGSize(width: pieceSize, height: pieceSize)
            node.color = design.colors.randomElement()!
            node.colorBlendFactor = 0.5
            node.blendMode = .add
            terminal = h * CGFloat.random(in: 0.12...0.3)
            flipSpeed = .random(in: 10...22)
        }
        node.position = position
        node.zPosition = kind == .glitter ? 150 : .random(in: 0...100)
        if kind != .glitter {
            node.color = .black
            node.colorBlendFactor = 0
        }
        addChild(node)

        return Particle(
            node: node,
            kind: kind,
            position: position,
            velocity: velocity,
            drag: gravity / terminal,
            rotation: .random(in: 0...(2 * .pi)),
            rotationSpeed: rotationSpeed,
            flip: .random(in: 0...(2 * .pi)),
            flipSpeed: flipSpeed,
            flutterPhase: .random(in: 0...(2 * .pi)),
            flutterFrequency: .random(in: 2.5...5),
            flutterAmplitude: flutterAmplitude,
            size: pieceSize,
            life: life
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
            while spawners[i].accumulator >= 1, particles.count < maxParticles {
                spawners[i].accumulator -= 1
                particles.append(spawners[i].make())
            }
            if spawners[i].remaining <= 0 { spawners.remove(at: i) }
        }
    }

    private func step(dt: CGFloat) {
        let g = gravity
        let h = size.height
        let t = elapsed
        // Slowly changing wind field: varies with time and height.
        let windBase = (sin(t * 0.6) * 0.5 + sin(t * 1.7 + 1.3) * 0.3) * design.windStrength

        for i in particles.indices.reversed() {
            var p = particles[i]
            p.age += dt

            // Orientation affects drag: a piece facing the airflow slows more than one slicing edge-on.
            let facing = abs(cos(p.flip))
            let drag = p.drag * (0.55 + 0.9 * facing)

            p.velocity.dy -= g * dt
            let damping = max(0, 1 - drag * dt)
            p.velocity.dx *= damping
            p.velocity.dy *= damping

            // Flutter: side-to-side sway that only matters once the piece has slowed down.
            let speedFactor = 1 / (1 + (hypot(p.velocity.dx, p.velocity.dy) / (h * 0.4)))
            let sway = cos(t * p.flutterFrequency + p.flutterPhase) * p.flutterAmplitude * speedFactor
            let wind = windBase * h * 0.06 * (0.5 + p.position.y / h) * speedFactor

            p.position.x += (p.velocity.dx + sway + wind) * dt
            p.position.y += p.velocity.dy * dt

            // Tumble faster while moving fast, settle into a lazy spin while falling.
            let spinScale = 0.35 + 0.65 * min(1, hypot(p.velocity.dx, p.velocity.dy) / (h * 0.8))
            p.rotation += p.rotationSpeed * spinScale * dt
            p.flip += p.flipSpeed * (0.6 + 0.4 * spinScale) * dt

            let fade = min(1, (p.life - p.age) / 0.9)
            let dead = p.age >= p.life || p.position.y < -p.size * 2 || p.position.x < -200 || p.position.x > size.width + 200

            if dead {
                p.node.removeFromParent()
                particles.remove(at: i)
                continue
            }

            let node = p.node
            node.position = p.position
            node.zRotation = p.rotation
            let flipScale = cos(p.flip)
            switch p.kind {
            case .piece, .streamer:
                node.xScale = max(0.08, abs(flipScale))
                node.yScale = 1
                node.colorBlendFactor = 0.45 * (1 - abs(flipScale)) + (flipScale < 0 ? 0.12 : 0)
                node.alpha = fade
            case .glitter:
                // Twinkle: glitter catches the light only at certain angles.
                let twinkle = 0.25 + 0.75 * pow(abs(flipScale), 3)
                node.setScale(0.8 + 0.5 * abs(flipScale))
                node.alpha = fade * twinkle
            }
            particles[i] = p
        }
    }
}
