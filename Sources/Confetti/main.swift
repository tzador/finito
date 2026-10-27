import AppKit

// MARK: - Options

struct Options {
    var playSound = true

    static let usage = """
    confetti \(confettiVersion) — throw confetti across all your displays

    Usage: confetti [options]

    Options:
      -s, --silent      do not play the party sound
      -v, --version     print the version and exit
      -h, --help        show this help and exit

    Drop a file at ~/Library/Application Support/Confetti/party.wav
    (or .mp3, .m4a, .aiff, .caf) to replace the built-in party sound.
    """

    static func parse(_ args: [String]) -> Options {
        var options = Options()
        for arg in args {
            switch arg {
            case "-s", "--silent", "--no-sound":
                options.playSound = false
            case "-v", "--version":
                print(confettiVersion)
                exit(0)
            case "-h", "--help":
                print(usage)
                exit(0)
            default:
                FileHandle.standardError.write("confetti: unknown option '\(arg)'\n\(usage)\n".data(using: .utf8)!)
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
        confetti.fire()

        if options.playSound {
            let sound = PartySound()
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

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))
let app = NSApplication.shared
let delegate = CLIDelegate(options: options)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
