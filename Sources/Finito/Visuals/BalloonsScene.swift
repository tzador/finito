import SpriteKit

/// A bunch of balloons drifting up and off the top of the screen.
final class BalloonsScene: EffectScene {
    private struct Balloon {
        let node: SKNode
        var position: CGPoint
        let rise: CGFloat
        let phase: CGFloat
        let frequency: CGFloat
        let amplitude: CGFloat
        let height: CGFloat
    }

    private var balloons: [Balloon] = []
    private var texture: SKTexture!

    override var liveCount: Int { balloons.count }

    override func didMove(to view: SKView) {
        guard texture == nil else { return }
        texture = TextureFactory.make(size: CGSize(width: 96, height: 128)) { ctx, rect in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let body = CGRect(x: 4, y: 20, width: 88, height: 104)
            ctx.addEllipse(in: body)
            ctx.clip()
            // Shaded body: light toward the upper left, darker toward the lower right.
            let gradient = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: 1, alpha: 1), CGColor(gray: 0.82, alpha: 1), CGColor(gray: 0.55, alpha: 1),
            ] as CFArray, locations: [0, 0.6, 1])!
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 36, y: 92), startRadius: 4, endCenter: CGPoint(x: 48, y: 72), endRadius: 70, options: [.drawsAfterEndLocation])
            ctx.resetClip()
            // Knot.
            ctx.setFillColor(CGColor(gray: 0.7, alpha: 1))
            ctx.move(to: CGPoint(x: 48, y: 22))
            ctx.addLine(to: CGPoint(x: 40, y: 12))
            ctx.addLine(to: CGPoint(x: 56, y: 12))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    override func fire() {
        let w = width
        emit(count: 16, over: 2.6) { [unowned self] in
            let h = CGFloat.random(in: 90...150)
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(width: h * 0.75, height: h)
            sprite.color = OpenColor.mid.randomElement()!
            sprite.colorBlendFactor = 0.85
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)

            // Wavy string hanging below the knot.
            let string = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: h * 0.09))
            path.addCurve(to: CGPoint(x: 0, y: -h * 0.6), control1: CGPoint(x: h * 0.15, y: -h * 0.15), control2: CGPoint(x: -h * 0.15, y: -h * 0.4))
            string.path = path
            string.strokeColor = NSColor(white: 0.9, alpha: 0.8)
            string.lineWidth = 1.5

            let node = SKNode()
            node.addChild(string)
            node.addChild(sprite)
            node.zPosition = h
            let position = CGPoint(x: .random(in: 40...(w - 40)), y: -h * 0.7)
            node.position = position
            addChild(node)
            balloons.append(Balloon(
                node: node, position: position,
                rise: height * .random(in: 0.16...0.3),
                phase: .randomAngle, frequency: .random(in: 0.7...1.4), amplitude: .random(in: 20...60),
                height: h
            ))
        }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        for i in balloons.indices.reversed() {
            var b = balloons[i]
            b.position.y += b.rise * dt
            let sway = sin(t * b.frequency + b.phase)
            b.position.x += sway * b.amplitude * dt
            if b.position.y > height + b.height * 1.8 {
                b.node.removeFromParent()
                balloons.remove(at: i)
                continue
            }
            b.node.position = b.position
            b.node.zRotation = -cos(t * b.frequency + b.phase) * 0.12
            balloons[i] = b
        }
    }
}
