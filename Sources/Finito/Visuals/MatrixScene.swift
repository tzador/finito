import SpriteKit

/// Columns of green glyphs raining down the screen.
final class MatrixScene: EffectScene {
    private struct Stream {
        let x: CGFloat
        var row: CGFloat
        let speed: CGFloat          // rows per second
        let startAt: CGFloat
        let endAt: CGFloat
        var lastRow = -1
        var head: SKSpriteNode?
    }

    private struct Glyph {
        let node: SKSpriteNode
        var age: CGFloat = 0
        let life: CGFloat
    }

    private var streams: [Stream] = []
    private var glyphs: [Glyph] = []
    private var textures: [SKTexture] = []
    private let cell: CGFloat = 22
    private let green = NSColor.fromHex("#2fe86a")
    private let headColor = NSColor.fromHex("#d8ffe0")

    override var liveCount: Int { glyphs.count + streams.filter { $0.head != nil }.count }
    override var maxLive: Int { 3000 }

    override func didMove(to view: SKView) {
        guard textures.isEmpty else { return }
        let font = NSFont(name: "Menlo", size: 18) ?? NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
        var chars: [String] = (0x30A1...0x30FA).compactMap { Unicode.Scalar($0).map { String(Character($0)) } }
        chars += "0123456789Z:=*+-<>¦|".map(String.init)
        textures = chars.map { TextureFactory.glyph($0, size: cell, font: font) }
    }

    override func fire() {
        let columns = Int(width / cell) + 1
        for c in 0..<columns {
            streams.append(Stream(
                x: CGFloat(c) * cell + cell / 2, row: 0,
                speed: .random(in: 7...17),
                startAt: .random(in: 0...2.5),
                endAt: .random(in: 3.5...5)
            ))
        }
        after(6.5) {}   // keep the scene alive at least this long
    }

    override func step(dt: CGFloat) {
        let t = elapsed
        let rows = Int(height / cell) + 2
        for i in streams.indices {
            var s = streams[i]
            guard t >= s.startAt else { continue }
            if t >= s.endAt || s.row > CGFloat(rows) {
                s.head?.removeFromParent()
                s.head = nil
                streams[i] = s
                continue
            }
            if s.head == nil {
                let head = SKSpriteNode(texture: textures.randomElement())
                head.size = CGSize(width: cell, height: cell)
                head.color = headColor
                head.colorBlendFactor = 1
                head.zPosition = 10
                addChild(head)
                s.head = head
            }
            s.row += s.speed * dt
            let row = Int(s.row)
            let y = height - s.row * cell
            s.head?.position = CGPoint(x: s.x, y: y)
            if row != s.lastRow, liveCount < maxLive {
                s.lastRow = row
                s.head?.texture = textures.randomElement()
                let node = SKSpriteNode(texture: textures.randomElement())
                node.size = CGSize(width: cell, height: cell)
                node.position = CGPoint(x: s.x, y: height - CGFloat(row) * cell)
                node.color = green
                node.colorBlendFactor = 1
                addChild(node)
                glyphs.append(Glyph(node: node, life: .random(in: 0.9...2.2)))
            }
            streams[i] = s
        }

        for i in glyphs.indices.reversed() {
            var g = glyphs[i]
            g.age += dt
            if g.age >= g.life {
                g.node.removeFromParent()
                glyphs.remove(at: i)
                continue
            }
            if Int.random(in: 0..<60) == 0 { g.node.texture = textures.randomElement() }
            g.node.alpha = (1 - g.age / g.life) * 0.9
            glyphs[i] = g
        }
    }
}
