import SpriteKit

/// Every visual effect finito can show.
enum Visual: String, CaseIterable {
    case confetti, stars, bubbles, rainbow, fireworks, snow, balloons, hearts, lasers, matrix, fireflies, shockwave
    case none

    static var showable: [Visual] { allCases.filter { $0 != .none } }

    func makeScene(size: CGSize) -> EffectScene {
        let scene: EffectScene
        switch self {
        case .confetti: scene = ConfettiScene(size: size)
        case .stars: scene = StarsScene(size: size)
        case .bubbles: scene = BubblesScene(size: size)
        case .rainbow: scene = RainbowScene(size: size)
        case .fireworks: scene = FireworksScene(size: size)
        case .snow: scene = SnowScene(size: size)
        case .balloons: scene = BalloonsScene(size: size)
        case .hearts: scene = HeartsScene(size: size)
        case .lasers: scene = LasersScene(size: size)
        case .matrix: scene = MatrixScene(size: size)
        case .fireflies: scene = FirefliesScene(size: size)
        case .shockwave: scene = ShockwaveScene(size: size)
        case .none: scene = EffectScene(size: size)
        }
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        return scene
    }

    /// Sounds that suit this visual; a random pick draws from these.
    var pairedSounds: [Sound] {
        switch self {
        case .confetti: return [.party, .tada, .fanfare, .applause]
        case .stars: return [.chime, .sparkle, .powerup]
        case .bubbles: return [.pop, .chime, .sparkle]
        case .rainbow: return [.chime, .fanfare, .sparkle]
        case .fireworks: return [.party, .applause, .drumroll]
        case .snow: return [.chime, .sparkle]
        case .balloons: return [.party, .pop, .tada]
        case .hearts: return [.chime, .sparkle, .coin]
        case .lasers: return [.whoosh, .powerup, .coin]
        case .matrix: return [.coin, .powerup, .whoosh]
        case .fireflies: return [.chime, .sparkle]
        case .shockwave: return [.whoosh, .drumroll, .powerup]
        case .none: return Sound.audible
        }
    }
}
