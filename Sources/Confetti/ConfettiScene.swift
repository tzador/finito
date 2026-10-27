import SpriteKit

/// A hand-rolled confetti simulation rendered with SpriteKit sprites.
///
/// Each piece of confetti is a flat shape with air drag that depends on how it is oriented,
/// a tumbling 3D flip (faked with a local-axis scale and darkening when edge-on),
/// side-to-side flutter and a slowly changing wind field.
final class ConfettiScene: SKScene {
    var onIdle: (() -> Void)?
    var isIdle: Bool { particles.isEmpty && spawners.isEmpty }

    private struct Particle {
        let node: SKSpriteNode
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

    /// Emits particles for a duration at a rate, from a region with a direction.
    private struct Spawner {
        var remaining: CGFloat          // seconds left
        var rate: CGFloat               // particles per second
        var accumulator: CGFloat = 0
        let make: () -> Particle
    }

    private var particles: [Particle] = []
    private var spawners: [Spawner] = []
    private var textures: [SKTexture] = []
    private var lastTime: TimeInterval?
    private var elapsed: CGFloat = 0
    private var notifiedIdle = true

    private var gravity: CGFloat { size.height * 1.3 }
    private let maxParticles = 1400

    override func didMove(to view: SKView) {
        guard textures.isEmpty else { return }
        for shape in ConfettiShape.allCases {
            for color in OpenColor.mid {
                if let image = shape.image(color: color, size: 32) {
                    let texture = SKTexture(cgImage: image)
                    texture.filteringMode = .linear
                    textures.append(texture)
                }
            }
        }
    }

    // MARK: - Firing

    func burst() {
        notifiedIdle = false
        let w = size.width

        // Two party poppers in the bottom corners: a hard pop, then a short stream.
        let cannons: [(origin: CGPoint, angle: CGFloat)] = [
            (CGPoint(x: w * 0.03, y: -10), .pi / 2 - 0.62),
            (CGPoint(x: w * 0.97, y: -10), .pi / 2 + 0.62),
        ]
        for cannon in cannons {
            spawners.append(Spawner(remaining: 0.18, rate: 1500) { [unowned self] in
                self.cannonParticle(origin: cannon.origin, angle: cannon.angle, power: 1.0)
            })
            spawners.append(Spawner(remaining: 1.1, rate: 220) { [unowned self] in
                self.cannonParticle(origin: cannon.origin, angle: cannon.angle, power: 0.8)
            })
        }

        // A gentle rain from the top that fills the screen as the burst settles.
        spawners.append(Spawner(remaining: 2.6, rate: 110) { [unowned self] in
            self.rainParticle()
        })
    }

    private func cannonParticle(origin: CGPoint, angle: CGFloat, power: CGFloat) -> Particle {
        let h = size.height
        let spread = CGFloat.random(in: -0.5...0.5)
        let theta = angle + spread * abs(spread) * 2.4 // denser in the middle of the cone, up to ±0.6 rad
        let speed = h * CGFloat.random(in: 3.5...7.5) * power
        return makeParticle(
            position: CGPoint(x: origin.x + .random(in: -20...20), y: origin.y),
            velocity: CGVector(dx: cos(theta) * speed, dy: sin(theta) * speed),
            life: .random(in: 5.5...8.5)
        )
    }

    private func rainParticle() -> Particle {
        let h = size.height
        return makeParticle(
            position: CGPoint(x: .random(in: -20...(size.width + 20)), y: h + 30),
            velocity: CGVector(dx: .random(in: -h * 0.05...h * 0.05), dy: -h * .random(in: 0.05...0.2)),
            life: .random(in: 7...10)
        )
    }

    private func makeParticle(position: CGPoint, velocity: CGVector, life: CGFloat) -> Particle {
        let h = size.height
        let pieceSize = CGFloat.random(in: 9...22)
        let node = SKSpriteNode(texture: textures.randomElement())
        node.size = CGSize(width: pieceSize, height: pieceSize)
        node.position = position
        node.color = .black
        node.colorBlendFactor = 0
        node.zPosition = .random(in: 0...100)
        addChild(node)

        // Lighter (smaller) pieces have a lower terminal velocity: terminal = gravity / drag.
        let terminal = h * CGFloat.random(in: 0.09...0.22) * (pieceSize / 16).squareRoot()
        return Particle(
            node: node,
            position: position,
            velocity: velocity,
            drag: gravity / terminal,
            rotation: .random(in: 0...(2 * .pi)),
            rotationSpeed: .random(in: -6...6),
            flip: .random(in: 0...(2 * .pi)),
            flipSpeed: .random(in: 4...11) * (Bool.random() ? 1 : -1),
            flutterPhase: .random(in: 0...(2 * .pi)),
            flutterFrequency: .random(in: 2.5...5),
            flutterAmplitude: h * .random(in: 0.08...0.2),
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
        let windBase = sin(t * 0.6) * 0.5 + sin(t * 1.7 + 1.3) * 0.3

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
            node.xScale = max(0.08, abs(flipScale))
            node.yScale = 1
            node.colorBlendFactor = 0.45 * (1 - abs(flipScale)) + (flipScale < 0 ? 0.12 : 0)
            node.alpha = fade
            particles[i] = p
        }
    }
}

