import SpriteKit

/// Eighties laser show: coloured beams sweeping out from the bottom corners with a soft bloom.
final class LasersScene: EffectScene {
    private struct Beam {
        let node: SKSpriteNode
        let origin: CGPoint
        let baseAngle: CGFloat
        let amplitude: CGFloat
        let frequency: CGFloat
        let phase: CGFloat
    }

    private var beams: [Beam] = []
    private var finished = false
    private let fadeIn: CGFloat = 0.4
    private let run: CGFloat = 3.6
    private let fadeOut: CGFloat = 0.7
    private let colors = ["#22b8cf", "#f06595", "#51cf66", "#fcc419", "#845ef7", "#ff922b", "#339af0", "#ff6b6b"].map(NSColor.fromHex)

    override var liveCount: Int { finished ? 0 : 1 }

    override func fire() {
        let w = width, h = height
        let length = hypot(w, h) * 1.1
        let core = TextureFactory.beam(length: 512, thickness: 8)
        let halo = TextureFactory.beam(length: 512, thickness: 8)
        let corners: [(CGPoint, CGFloat)] = [(CGPoint(x: -10, y: -10), .pi * 0.25), (CGPoint(x: w + 10, y: -10), .pi * 0.75)]
        for i in 0..<8 {
            let (origin, base) = corners[i % 2]
            let node = SKSpriteNode(texture: core)
            node.size = CGSize(width: length, height: 5)
            node.anchorPoint = CGPoint(x: 0, y: 0.5)
            node.position = origin
            node.color = colors[i]
            node.colorBlendFactor = 1
            node.blendMode = .add
            node.alpha = 0

            let bloom = SKSpriteNode(texture: halo)
            bloom.size = CGSize(width: length, height: 36)
            bloom.anchorPoint = CGPoint(x: 0, y: 0.5)
            bloom.color = colors[i]
            bloom.colorBlendFactor = 1
            bloom.blendMode = .add
            bloom.alpha = 0.35
            node.addChild(bloom)
            addChild(node)
            beams.append(Beam(
                node: node, origin: origin, baseAngle: base,
                amplitude: .random(in: 0.45...0.75), frequency: .random(in: 0.8...1.8), phase: .randomAngle
            ))
        }
        after(fadeIn + run + fadeOut) { [unowned self] in
            beams.forEach { $0.node.removeFromParent() }
            finished = true
        }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        let env = lifeEnvelope(age: t, life: fadeIn + run + fadeOut, inSeconds: fadeIn, outSeconds: fadeOut)
        for b in beams {
            b.node.zRotation = b.baseAngle + sin(t * b.frequency + b.phase) * b.amplitude + sin(t * b.frequency * 2.7 + b.phase) * 0.08
            b.node.alpha = env * (0.8 + 0.2 * sin(t * 9 + b.phase))
        }
    }
}
