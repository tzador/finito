import AppKit
import QuartzCore

/// Shows a click-through, transparent overlay on every connected display and fires confetti on each.
final class ConfettiController {
    private var windows: [ConfettiWindow] = []
    private var generation = 0

    private static let burstDuration: TimeInterval = 1.6
    private static let settleDuration: TimeInterval = 7.0

    func fire() {
        generation += 1
        let gen = generation

        if windows.isEmpty {
            windows = NSScreen.screens.map(ConfettiWindow.init(screen:))
            windows.forEach { $0.orderFrontRegardless() }
        }
        windows.forEach { $0.burst(duration: Self.burstDuration) }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDuration) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.windows.forEach { $0.orderOut(nil) }
            self.windows.removeAll()
        }
    }
}

final class ConfettiWindow: NSWindow {
    private let emitters: [CAEmitterLayer]

    init(screen: NSScreen) {
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let size = screen.frame.size
        let launchSpots: [(CGPoint, CGFloat)] = [
            (CGPoint(x: size.width * 0.02, y: 0), .pi / 2 - 0.55),   // bottom-left, aiming up-right
            (CGPoint(x: size.width * 0.98, y: 0), .pi / 2 + 0.55),   // bottom-right, aiming up-left
        ]
        emitters = launchSpots.map { Self.makeEmitter(at: $0.0, angle: $0.1, screenSize: size) }
        emitters.forEach { view.layer?.addSublayer($0) }

        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        contentView = view
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    func burst(duration: TimeInterval) {
        let now = CACurrentMediaTime()
        for emitter in emitters {
            emitter.beginTime = now
            emitter.birthRate = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.emitters.forEach { $0.birthRate = 0 }
        }
    }

    private static func makeEmitter(at point: CGPoint, angle: CGFloat, screenSize: CGSize) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = CGRect(origin: .zero, size: screenSize)
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.emitterMode = .outline
        emitter.renderMode = .oldestFirst
        emitter.birthRate = 0
        emitter.seed = UInt32.random(in: 0...UInt32.max)

        // Scale velocity with screen height so it looks right on any display.
        let launchSpeed = screenSize.height * 1.15
        var cells: [CAEmitterCell] = []
        for shape in ConfettiShape.allCases {
            for color in OpenColor.mid {
                guard let image = shape.image(color: color, size: 18) else { continue }
                let cell = CAEmitterCell()
                cell.contents = image
                cell.birthRate = 1.3
                cell.lifetime = 7
                cell.lifetimeRange = 1.5
                cell.velocity = launchSpeed
                cell.velocityRange = launchSpeed * 0.35
                cell.emissionLongitude = angle
                cell.emissionRange = 0.42
                cell.yAcceleration = -screenSize.height * 0.9
                cell.xAcceleration = 0
                cell.scale = 0.9
                cell.scaleRange = 0.5
                cell.spin = 4
                cell.spinRange = 10
                cell.alphaSpeed = -0.12
                cells.append(cell)
            }
        }
        emitter.emitterCells = cells
        return emitter
    }
}
