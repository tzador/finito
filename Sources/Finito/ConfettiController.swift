import AppKit
import SpriteKit

/// Shows a click-through, transparent overlay on every connected display and fires confetti on each.
final class ConfettiController {
    private var windows: [ConfettiWindow] = []
    /// Called once every display has finished its animation and the overlays are gone.
    var onFinished: (() -> Void)?

    func fire() {
        if windows.isEmpty {
            windows = NSScreen.screens.map { screen in
                let window = ConfettiWindow(screen: screen)
                window.onFinished = { [weak self] in self?.windowFinished() }
                return window
            }
            windows.forEach { $0.orderFrontRegardless() }
        }
        windows.forEach { $0.burst() }
    }

    private func windowFinished() {
        guard windows.allSatisfy({ $0.isFinished }) else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        onFinished?()
    }
}

final class ConfettiWindow: NSWindow {
    private let skView: SKView
    private let scene: ConfettiScene
    var onFinished: (() -> Void)?
    var isFinished: Bool { scene.isIdle }

    init(screen: NSScreen) {
        let size = screen.frame.size
        skView = SKView(frame: NSRect(origin: .zero, size: size))
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
        skView.wantsLayer = true
        skView.layer?.backgroundColor = .clear

        scene = ConfettiScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear

        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        contentView = skView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false

        scene.onIdle = { [weak self] in self?.onFinished?() }
        skView.presentScene(scene)
    }

    func burst() {
        scene.burst()
    }

    override func orderOut(_ sender: Any?) {
        skView.isPaused = true
        super.orderOut(sender)
    }
}
