import AppKit

// MARK: - Options

struct Options {
    var playSound = true
    var wait = false
    var seed: UInt32?
    /// Internal: drive only this display. Set by the parent on each drawing child it spawns.
    var display: CGDirectDisplayID?
    /// Internal: play the sound and nothing else. Set by the parent on the sound child.
    var soundOnly = false

    static let usage = """
    finito \(finitoVersion) — blow autumn leaves across all your displays

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
            case "--display":
                let value = parts.count > 1 ? parts[1] : iterator.next()
                guard let value, let display = CGDirectDisplayID(value) else {
                    FileHandle.standardError.write("finito: --display needs a display ID\n".data(using: .utf8)!)
                    exit(2)
                }
                options.display = display
                options.wait = true
            case "--sound-only":
                options.soundOnly = true
                options.wait = true
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
    /// Displays to cover in this process, or `nil` for all of them.
    let displays: [CGDirectDisplayID]?
    private let confetti = ConfettiController()
    private var sound: PartySound?
    private var overlayDone = false
    private var soundDone = false

    init(options: Options, displays: [CGDirectDisplayID]?) {
        self.options = options
        self.displays = displays
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        confetti.onFinished = { [weak self] in
            self?.overlayDone = true
            self?.exitIfDone()
        }
        confetti.fire(seed: options.seed ?? 1, displays: displays)

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

// Every display gets a process of its own, and so does the sound. SpriteKit drives all of a
// process's views from one shared frame scheduler, and with views on two different displays one
// of them is starved to a few frames per second, so that screen crawls and the show never ends.
// The parent spawns one detached drawing child per display plus one child that only plays the
// sound, and either returns right away or, with `--wait`, waits for all of them.
var displays: [CGDirectDisplayID]? = options.display.map { [$0] }
if options.soundOnly { displays = [] }
var children: [pid_t] = []
if options.display == nil, !options.soundOnly {
    let connected = NSScreen.screens.compactMap(\.displayID)
    do {
        for display in connected {
            let childArguments = ["--display", String(display), "--seed", String(options.seed!), "--silent"]
            children.append(try spawnDetached(arguments: childArguments))
        }
        if options.playSound {
            children.append(try spawnDetached(arguments: ["--sound-only", "--seed", String(options.seed!)]))
        }
        if options.wait {
            for pid in children {
                var status: Int32 = 0
                waitpid(pid, &status, 0)
            }
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("finito: \(error); running in the foreground\n".data(using: .utf8)!)
        // The drawing children spawned before the failure cover their displays; the sound child
        // is spawned last, so it never got started. Do the rest in this process.
        displays = Array(connected.dropFirst(children.count))
    }
}

let app = NSApplication.shared
let delegate = CLIDelegate(options: options, displays: displays)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
