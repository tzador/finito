import AVFoundation
import AppKit

/// Plays a party sound. Uses a user-supplied file if present at
/// ~/Library/Application Support/Confetti/party.(wav|mp3|m4a|aiff), otherwise a synthesized pop + fanfare.
final class PartySound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var customSound: NSSound?

    init() {
        customSound = Self.loadCustomSound()
        guard customSound == nil else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffer = Self.synthesize(format: format)
    }

    func play() {
        if let customSound {
            customSound.stop()
            customSound.play()
            return
        }
        guard let buffer else { return }
        do {
            if !engine.isRunning { try engine.start() }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } catch {
            NSLog("Audio engine failed: \(error)")
        }
    }

    private static func loadCustomSound() -> NSSound? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("Confetti")
        for ext in ["wav", "mp3", "m4a", "aiff", "aif", "caf"] {
            let url = dir.appendingPathComponent("party.\(ext)")
            if FileManager.default.fileExists(atPath: url.path), let sound = NSSound(contentsOf: url, byReference: false) {
                return sound
            }
        }
        return nil
    }

    /// A short "pop" (noise burst) followed by a rising major arpeggio with a bright, chiptune-ish timbre.
    private static func synthesize(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = Float(format.sampleRate)
        let duration: Float = 1.6
        let frames = AVAudioFrameCount(duration * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let out = buffer.floatChannelData?[0] else { return nil }

        // Pop: short filtered noise burst with fast decay.
        var noiseState: UInt32 = 12345
        var lowpass: Float = 0
        for i in 0..<Int(0.12 * sr) {
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            let white = Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
            lowpass += 0.25 * (white - lowpass)
            let t = Float(i) / sr
            let env = expf(-t * 45)
            out[i] += lowpass * env * 0.9
        }

        // Fanfare: C5 E5 G5 C6, then a sustained C6+E6+G6 chord.
        let notes: [(freqs: [Float], start: Float, length: Float)] = [
            ([523.25], 0.10, 0.14),
            ([659.25], 0.24, 0.14),
            ([783.99], 0.38, 0.14),
            ([1046.50], 0.52, 0.22),
            ([1046.50, 1318.51, 1567.98], 0.74, 0.80),
        ]
        for note in notes {
            let startFrame = Int(note.start * sr)
            let noteFrames = Int(note.length * sr)
            for i in 0..<noteFrames where startFrame + i < Int(frames) {
                let t = Float(i) / sr
                let attack = min(1, t / 0.01)
                let release = min(1, max(0, (note.length - t) / 0.08))
                let decay = expf(-t * 1.8)
                let env = attack * release * decay
                var sample: Float = 0
                for f in note.freqs {
                    let phase = 2 * Float.pi * f * t
                    // Mix of sine + a bit of square + an octave for sparkle.
                    sample += sinf(phase) * 0.6 + (sinf(phase) > 0 ? 0.15 : -0.15) + sinf(phase * 2) * 0.15
                }
                sample /= Float(note.freqs.count)
                out[startFrame + i] += sample * env * 0.35
            }
        }

        // Soft clip to be safe.
        for i in 0..<Int(frames) {
            out[i] = tanhf(out[i])
        }
        return buffer
    }
}
