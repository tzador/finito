import AppKit
import ServiceManagement

@main
struct ConfettiMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let confetti = ConfettiController()
    private let sound = PartySound()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let playSound = "playSound"
        static let userDisabledLoginItem = "userDisabledLoginItem"
    }

    private var playSoundEnabled: Bool {
        get { defaults.object(forKey: Keys.playSound) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.playSound) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerLoginItemIfNeeded()

        if CommandLine.arguments.contains("--fire") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.triggerConfetti() }
        }
    }

    // MARK: - Status item / menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "party.popper.fill", accessibilityDescription: "Confetti")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self

        let fire = NSMenuItem(title: "Trigger Confetti", action: #selector(triggerConfetti), keyEquivalent: "t")
        fire.target = self
        menu.addItem(fire)

        menu.addItem(.separator())

        let soundItem = NSMenuItem(title: "Play Party Sound", action: #selector(togglePlaySound(_:)), keyEquivalent: "")
        soundItem.target = self
        soundItem.tag = MenuTag.sound.rawValue
        menu.addItem(soundItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = MenuTag.login.rawValue
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Confetti", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private enum MenuTag: Int { case sound = 1, login = 2 }

    @objc private func triggerConfetti() {
        confetti.fire()
        if playSoundEnabled { sound.play() }
    }

    @objc private func togglePlaySound(_ sender: NSMenuItem) {
        playSoundEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                defaults.set(true, forKey: Keys.userDisabledLoginItem)
            } else {
                try service.register()
                defaults.set(false, forKey: Keys.userDisabledLoginItem)
            }
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Login item

    /// Registers the app as a login item on launch unless the user turned it off in the menu.
    /// Re-registering on every launch keeps the login item pointing at the current app location.
    private func registerLoginItemIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        guard !defaults.bool(forKey: Keys.userDisabledLoginItem) else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Could not register login item: \(error)")
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: MenuTag.sound.rawValue)?.state = playSoundEnabled ? .on : .off
        let loginItem = menu.item(withTag: MenuTag.login.rawValue)
        let status = SMAppService.mainApp.status
        loginItem?.state = status == .enabled ? .on : .off
        loginItem?.isEnabled = Bundle.main.bundlePath.hasSuffix(".app")
    }
}
