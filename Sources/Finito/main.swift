import AppKit

// MARK: - Options

struct Options {
    var playSound = true
    var wait = false
    var seed: UInt32?

    static let usage = """
    finito \(finitoVersion) — throw confetti across all your displays

    Usage: finito [options]

    Options:
      -s, --silent      do not play the party sound
      --seed N          replay a particular show (each run composes a new one)
      -w, --wait        stay in the foreground until the animation and sound finish
      -v, --version     print the version and exit
      -h, --help        show this help and exit

    Positional arguments are ignored, so finito works as-is as a hook or
    notify command for Claude Code and Codex (see the README).

    Drop a file at ~/Library/Application Support/Finito/party.wav
    (or .mp3, .m4a, .aiff, .caf) to replace the built-in party sound.
    """

    static func parse(_ args: [String]) -> Options {
        var options = Options()
        var iterator = args.makeIterator()
        while let raw = iterator.next() {
            let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
            let arg = parts[0]
            switch arg {
            case "-s", "--silent", "--no-sound":
                options.playSound = false
            case "--seed":
                let value = parts.count > 1 ? parts[1] : iterator.next()
                guard let value, let seed = UInt32(value) else {
                    FileHandle.standardError.write("finito: --seed needs a number\n".data(using: .utf8)!)
                    exit(2)
                }
                options.seed = seed
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
                FileHandle.standardError.write("finito: unknown option '\(arg)'\n\(usage)\n".data(using: .utf8)!)
                exit(2)
            }
        }
        return options
    }
}

// MARK: - App

final class CLIDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    private let confetti = ConfettiController()
    private var sound: PartySound?
    private var overlayDone = false
    private var soundDone = false

    init(options: Options) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        confetti.onFinished = { [weak self] in
            self?.overlayDone = true
            self?.exitIfDone()
        }
        confetti.fire(seed: options.seed ?? 1)

        if options.playSound {
            let sound = PartySound(seed: options.seed ?? 1)
            self.sound = sound
            sound.play { [weak self] in
                self?.soundDone = true
                self?.exitIfDone()
            }
        } else {
            soundDone = true
        }
    }

    private func exitIfDone() {
        guard overlayDone, soundDone else { return }
        exit(0)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
var options = Options.parse(arguments)

// Compose a different jingle every launch unless a seed was given. The seed is passed on to
// the detached child so what plays is what this process chose.
if options.seed == nil {
    options.seed = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)) ^ UInt32(getpid())
}

// By default, hand the show off to a detached copy of ourselves and return the terminal
// immediately. `--wait` keeps the original blocking behaviour for scripts that need it.
if !options.wait {
    do {
        _ = try spawnDetached(arguments: arguments + ["--seed", String(options.seed!), "--wait"])
        exit(0)
    } catch {
        FileHandle.standardError.write("finito: \(error); running in the foreground\n".data(using: .utf8)!)
    }
}

let app = NSApplication.shared
let delegate = CLIDelegate(options: options)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
