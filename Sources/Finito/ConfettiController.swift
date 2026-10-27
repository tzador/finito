import AppKit
import SpriteKit

/// Shows a click-through, transparent overlay on the requested displays and fires confetti on each.
///
/// Normally a process drives exactly one display (see `main.swift`): SpriteKit schedules every
/// `SKView` in a process through one shared frame callback, and with views on two different
/// displays one of them is starved down to a few frames per second.
final class ConfettiController {
    private var windows: [ConfettiWindow] = []
    /// Called once every display has finished its animation and the overlays are gone.
    var onFinished: (() -> Void)?

    /// - Parameter displays: the displays to cover, or `nil` for every connected display. An
    ///   empty list shows nothing and finishes at once (the sound-only process uses this).
    func fire(seed: UInt32, displays: [CGDirectDisplayID]? = nil) {
        if windows.isEmpty {
            let screens = NSScreen.screens.filter { screen in
                displays.map { ids in screen.displayID.map(ids.contains) ?? false } ?? true
            }
            windows = screens.map { screen in
                let window = ConfettiWindow(screen: screen, seed: seed)
                window.onFinished = { [weak self] in self?.windowFinished() }
                return window
            }
            windows.forEach { $0.orderFrontRegardless() }
        }
        guard !windows.isEmpty else {
            // Nothing to show (sound-only process, or the display was unplugged between spawn
            // and launch): finish right away.
            DispatchQueue.main.async { [weak self] in self?.onFinished?() }
            return
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

extension NSScreen {
    /// The Core Graphics display ID backing this screen; stable across processes, unlike the
    /// index in `NSScreen.screens`.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}

final class ConfettiWindow: NSWindow {
    private let skView: SKView
    private let scene: ConfettiScene
    var onFinished: (() -> Void)?
    var isFinished: Bool { scene.isIdle }

    init(screen: NSScreen, seed: UInt32) {
        let size = screen.frame.size
        skView = SKView(frame: NSRect(origin: .zero, size: size))
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
        skView.wantsLayer = true
        skView.layer?.backgroundColor = .clear

        scene = ConfettiScene(size: size, seed: seed)
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
