import SpriteKit

/// Translucent soap bubbles rising with a wobble, each popping into a ring of droplets.
final class BubblesScene: EffectScene {
    private struct Bubble {
        let node: SKSpriteNode
        var position: CGPoint
        let rise: CGFloat
        let phase: CGFloat
        let frequency: CGFloat
        let amplitude: CGFloat
        let size: CGFloat
        var age: CGFloat = 0
        let popAt: CGFloat
    }

    private struct Droplet {
        let node: SKSpriteNode
        var position: CGPoint
        var velocity: CGVector
        var age: CGFloat = 0
        let life: CGFloat
    }

    private var bubbles: [Bubble] = []
    private var droplets: [Droplet] = []
    private var bubbleTexture: SKTexture!
    private var dropTexture: SKTexture!
    private let tints = ["#a5d8ff", "#d0bfff", "#fcc2d7", "#c3fae8", "#fff3bf", "#ffffff"].map(NSColor.fromHex)

    override var liveCount: Int { bubbles.count + droplets.count }

    override func didMove(to view: SKView) {
        guard bubbleTexture == nil else { return }
        bubbleTexture = TextureFactory.make(size: 128) { ctx, rect in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2 - 2
            // Body: nearly clear centre, milky toward the edge, with a bright rim.
            let body = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: 1, alpha: 0.04), CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0),
            ] as CFArray, locations: [0, 0.75, 0.96, 1])!
            ctx.drawRadialGradient(body, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            // Highlight: a soft ellipse in the upper left.
            ctx.saveGState()
            ctx.translateBy(x: c.x - r * 0.38, y: c.y + r * 0.42)
            ctx.rotate(by: .pi / 4)
            let highlight = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.85), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
            ctx.scaleBy(x: 1, y: 0.45)
            ctx.drawRadialGradient(highlight, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 0.42, options: [])
            ctx.restoreGState()
        }
        dropTexture = TextureFactory.glow(size: 16, hardness: 0.6)
    }

    override func fire() {
        let w = width
        emit(count: 70, over: 2.8) { [unowned self] in
            let size = CGFloat.random(in: 40...150)
            let node = SKSpriteNode(texture: bubbleTexture)
            node.size = CGSize(width: size, height: size)
            node.color = tints.randomElement()!
            node.colorBlendFactor = 0.35
            node.alpha = 0
            node.zPosition = size
            let position = CGPoint(x: .random(in: 0...w), y: -size)
            node.position = position
            addChild(node)
            bubbles.append(Bubble(
                node: node, position: position,
                rise: height * .random(in: 0.12...0.28) * (60 / size).squareRoot(),
                phase: .randomAngle, frequency: .random(in: 1.2...2.6), amplitude: .random(in: 10...40),
                size: size, popAt: .random(in: 2.5...7)
            ))
        }
    }

    private func pop(_ b: Bubble) {
        let count = Int(6 + b.size / 12)
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + .random(in: -0.2...0.2)
            let speed = b.size * .random(in: 1.5...3)
            let node = SKSpriteNode(texture: dropTexture)
            let d = CGFloat.random(in: 3...7)
            node.size = CGSize(width: d, height: d)
            node.position = b.position
            node.color = b.node.color
            node.colorBlendFactor = 0.5
            node.zPosition = b.node.zPosition
            addChild(node)
            droplets.append(Droplet(
                node: node, position: b.position,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                life: .random(in: 0.5...0.9)
            ))
        }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        for i in bubbles.indices.reversed() {
            var b = bubbles[i]
            b.age += dt
            b.position.y += b.rise * dt
            b.position.x += cos(t * b.frequency + b.phase) * b.amplitude * dt
            if b.age >= b.popAt || b.position.y > height + b.size {
                if b.position.y <= height + b.size { pop(b) }
                b.node.removeFromParent()
                bubbles.remove(at: i)
                continue
            }
            b.node.position = b.position
            b.node.alpha = min(1, b.age / 0.5)
            // Jelly-like wobble.
            b.node.xScale = 1 + 0.06 * sin(t * b.frequency * 2.3 + b.phase)
            b.node.yScale = 1 - 0.06 * sin(t * b.frequency * 2.3 + b.phase)
            bubbles[i] = b
        }

        let g = height * 1.6
        for i in droplets.indices.reversed() {
            var d = droplets[i]
            d.age += dt
            if d.age >= d.life {
                d.node.removeFromParent()
                droplets.remove(at: i)
                continue
            }
            d.velocity.dy -= g * dt
            d.velocity.dx *= max(0, 1 - 2 * dt)
            d.position.x += d.velocity.dx * dt
            d.position.y += d.velocity.dy * dt
            d.node.position = d.position
            d.node.alpha = 1 - d.age / d.life
            droplets[i] = d
        }
    }
}
