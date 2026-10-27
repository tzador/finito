import SpriteKit

/// Soft snowfall that piles into a thin drift along the bottom edge before melting away.
final class SnowScene: EffectScene {
    private struct Flake {
        let node: SKSpriteNode
        var position: CGPoint
        let fall: CGFloat
        let phase: CGFloat
        let frequency: CGFloat
        let amplitude: CGFloat
        let floor: CGFloat
        var landed = false
        var age: CGFloat = 0
    }

    private var flakes: [Flake] = []
    private var texture: SKTexture!
    private var meltStart: CGFloat?
    private let meltDuration: CGFloat = 1.4

    override var liveCount: Int { flakes.count }
    override var maxLive: Int { 1100 }

    override func didMove(to view: SKView) {
        guard texture == nil else { return }
        texture = TextureFactory.glow(size: 24, hardness: 0.45)
    }

    override func fire() {
        let w = width
        emit(for: 4.2, rate: 200) { [unowned self] in
            let d = CGFloat.random(in: 4...11)
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(width: d, height: d)
            node.alpha = 0
            node.zPosition = d
            let position = CGPoint(x: .random(in: -30...(w + 30)), y: height + 20)
            node.position = position
            addChild(node)
            flakes.append(Flake(
                node: node, position: position,
                fall: height * .random(in: 0.08...0.2) * (d / 8).squareRoot(),
                phase: .randomAngle, frequency: .random(in: 0.8...2.2), amplitude: .random(in: 15...45),
                floor: .random(in: -2...14)
            ))
        }
        after(6.8) { [unowned self] in meltStart = elapsed }
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        let wind = sin(t * 0.4) * 25
        let melt = meltStart.map { max(0, 1 - (t - $0) / meltDuration) } ?? 1
        for i in flakes.indices.reversed() {
            var f = flakes[i]
            f.age += dt
            if melt <= 0 {
                f.node.removeFromParent()
                flakes.remove(at: i)
                continue
            }
            if !f.landed {
                f.position.y -= f.fall * dt
                f.position.x += (cos(t * f.frequency + f.phase) * f.amplitude + wind) * dt
                if f.position.y <= f.floor { f.landed = true; f.position.y = f.floor }
            }
            f.node.position = f.position
            f.node.alpha = min(1, f.age / 0.8) * melt * (f.landed ? 0.85 : 0.95)
            flakes[i] = f
        }
    }
}
