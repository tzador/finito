import AVFoundation
import AppKit

/// What to play: a built-in synthesized sound or a user-supplied file.
enum SoundChoice {
    case builtin(Sound)
    case file(name: String, url: URL)

    var name: String {
        switch self {
        case .builtin(let sound): return sound.rawValue
        case .file(let name, _): return name
        }
    }

    static let supportedExtensions = ["wav", "mp3", "m4a", "aiff", "aif", "caf"]

    /// `~/Library/Application Support/Finito/sounds`
    static var customDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Finito").appendingPathComponent("sounds")
    }

    /// Names of user-supplied sounds, from files in the custom directory.
    static var customNames: [String] {
        guard let dir = customDirectory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.compactMap { file in
            let url = URL(fileURLWithPath: file)
            return supportedExtensions.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : nil
        }.sorted()
    }

    /// Resolves a name given on the command line. Custom files shadow built-ins of the same name.
    static func named(_ name: String) -> SoundChoice? {
        if let url = customFile(named: name) { return .file(name: name, url: url) }
        if let sound = Sound(rawValue: name) { return .builtin(sound) }
        return nil
    }

    private static func customFile(named name: String) -> URL? {
        var candidates: [URL] = []
        if let dir = customDirectory {
            candidates += supportedExtensions.map { dir.appendingPathComponent("\(name).\($0)") }
        }
        // Legacy location for the party sound: ~/Library/Application Support/Finito/party.wav
        if name == Sound.party.rawValue, let legacy = customDirectory?.deletingLastPathComponent() {
            candidates += supportedExtensions.map { legacy.appendingPathComponent("party.\($0)") }
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Plays a sound once and reports when it has finished.
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var fileSound: NSSound?

    init(_ choice: SoundChoice) {
        switch choice {
        case .file(_, let url):
            fileSound = NSSound(contentsOf: url, byReference: false)
        case .builtin(let sound):
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            let mix = sound.render(sampleRate: Float(format.sampleRate))
            buffer = Self.buffer(from: mix, format: format)
        }
    }

    /// Plays the sound; `completion` runs on the main queue once playback has finished.
    func play(completion: (() -> Void)? = nil) {
        if let fileSound {
            fileSound.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + fileSound.duration + 0.1) { completion?() }
            return
        }
        guard let buffer else { completion?(); return }
        do {
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { _ in
                DispatchQueue.main.async { completion?() }
            }
            player.play()
        } catch {
            NSLog("Audio engine failed: \(error)")
            completion?()
        }
    }

    private static func buffer(from mix: Mixer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = mix.frames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        mix.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: frames) }
        mix.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: frames) }
        return buffer
    }
}
