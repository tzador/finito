import AppKit

// MARK: - Options

struct Options {
    var visual: Visual?
    var sound: SoundChoice?
    var wait = false

    static let usage = """
    finito \(finitoVersion) — celebrate across all your displays

    Usage: finito [options]

    Options:
      -V, --visual NAME   visual effect to show (default: random)
      -S, --sound NAME    sound to play (default: one that fits the visual)
      -s, --silent        do not play a sound (same as --sound none)
      -l, --list          list the available visuals and sounds
      -w, --wait          stay in the foreground until the show is over
      -v, --version       print the version and exit
      -h, --help          show this help and exit

    Positional arguments are ignored, so finito works as-is as a hook or
    notify command for Claude Code and Codex (see the README).

    Drop audio files (wav, mp3, m4a, aiff, caf) into
    ~/Library/Application Support/Finito/sounds/ to add your own sounds;
    the file name becomes the sound name.
    """

    static func parse(_ args: [String]) -> Options {
        var options = Options()
        var iterator = args.makeIterator()

        func value(for flag: String, inline: String?) -> String {
            if let inline { return inline }
            guard let next = iterator.next() else { fail("option '\(flag)' needs a value") }
            return next
        }

        while let raw = iterator.next() {
            let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
            let arg = parts[0]
            let inline = parts.count > 1 ? parts[1] : nil
            switch arg {
            case "-V", "--visual":
                let name = value(for: arg, inline: inline)
                guard let visual = Visual(rawValue: name) else { fail("unknown visual '\(name)'; see --list") }
                options.visual = visual
            case "-S", "--sound":
                let name = value(for: arg, inline: inline)
                guard let sound = SoundChoice.named(name) else { fail("unknown sound '\(name)'; see --list") }
                options.sound = sound
            case "-s", "--silent", "--no-sound":
                options.sound = .builtin(.none)
            case "-l", "--list":
                print("visuals: " + Visual.allCases.map(\.rawValue).joined(separator: " "))
                print("sounds:  " + Sound.allCases.map(\.rawValue).joined(separator: " "))
                let custom = SoundChoice.customNames
                if !custom.isEmpty { print("custom:  " + custom.joined(separator: " ")) }
                exit(0)
            case "-w", "--wait":
                options.wait = true
            case "-v", "--version":
                print(finitoVersion)
                exit(0)
            case "-h", "--help":
                print(usage)
                exit(0)
            case _ where !arg.hasPrefix("-"):
                // Positional arguments are ignored so finito can be used directly as a
                // Codex `notify` program, which passes a JSON payload as the first argument.
                continue
            default:
                fail("unknown option '\(arg)'")
            }
        }
        return options
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write("finito: \(message)\n\(usage)\n".data(using: .utf8)!)
        exit(2)
    }
}

// MARK: - App

final class CLIDelegate: NSObject, NSApplicationDelegate {
    let visual: Visual
    let sound: SoundChoice
    private let effects = EffectController()
    private var player: SoundPlayer?
    private var visualDone = false
    private var soundDone = false

    init(visual: Visual, sound: SoundChoice) {
        self.visual = visual
        self.sound = sound
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        effects.onFinished = { [weak self] in
            self?.visualDone = true
            self?.exitIfDone()
        }
        effects.fire(visual)

        if case .builtin(.none) = sound {
            soundDone = true
        } else {
            let player = SoundPlayer(sound)
            self.player = player
            player.play { [weak self] in
                self?.soundDone = true
                self?.exitIfDone()
            }
        }
        exitIfDone()
    }

    private func exitIfDone() {
        guard visualDone, soundDone else { return }
        exit(0)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let options = Options.parse(arguments)

// Pick what was not specified: a random visual, then a sound that suits it.
let visual = options.visual ?? Visual.showable.randomElement()!
let sound = options.sound ?? .builtin(visual.pairedSounds.randomElement()!)

// By default, hand the show off to a detached copy of ourselves and return the terminal
// immediately. `--wait` keeps the original blocking behaviour for scripts that need it.
if !options.wait {
    do {
        _ = try spawnDetached(arguments: ["--visual", visual.rawValue, "--sound", sound.name, "--wait"])
        exit(0)
    } catch {
        FileHandle.standardError.write("finito: \(error); running in the foreground\n".data(using: .utf8)!)
    }
}

let app = NSApplication.shared
let delegate = CLIDelegate(visual: visual, sound: sound)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
