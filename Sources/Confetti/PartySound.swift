import AVFoundation
import AppKit

/// Plays a party sound. Uses a user-supplied file if present at
/// ~/Library/Application Support/Confetti/party.(wav|mp3|m4a|aiff), otherwise a synthesized one.
final class PartySound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var customSound: NSSound?

    init() {
        customSound = Self.loadCustomSound()
        guard customSound == nil else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffer = PartySoundSynth(sampleRate: Float(format.sampleRate)).render(into: format)
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
}

/// Procedural "party popper + sparkle + chord" sound, rendered once at startup.
///
/// Layers (all times in seconds from the trigger):
///   0.00  popper: sub thump, sharp crack, short whoosh
///   0.05  paper crackle: sparse random clicks as the confetti streams out
///   0.12  sparkle: ascending pentatonic bell glissando, panned left to right
///   0.15  chord swell: detuned saws through a closing low-pass, C major with an added 9th
/// Everything runs through a small stereo Schroeder reverb and a soft limiter.
struct PartySoundSynth {
    let sampleRate: Float
    private let duration: Float = 2.8

    func render(into format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = Int(duration * sampleRate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var rng = SeededRandom(seed: 0xC0FFEE)

        popper(&left, &right, &rng)
        crackle(&left, &right, &rng)
        sparkle(&left, &right)
        chord(&left, &right)

        let wetL = reverb(left, delayOffset: 0)
        let wetR = reverb(right, delayOffset: 31)
        for i in 0..<frames {
            left[i] = left[i] * 0.8 + wetL[i] * 0.28
            right[i] = right[i] * 0.8 + wetR[i] * 0.28
        }
        fadeOut(&left, &right, seconds: 0.2)
        normalizeAndLimit(&left, &right, peak: 0.85)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: frames) }
        right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: frames) }
        return buffer
    }

    // MARK: - Layers

    private func popper(_ l: inout [Float], _ r: inout [Float], _ rng: inout SeededRandom) {
        let n = Int(0.45 * sampleRate)
        var phase: Float = 0
        var lp: Float = 0, lp2: Float = 0
        for i in 0..<n {
            let t = Float(i) / sampleRate
            // Sub thump: pitch sweeps 220 -> 45 Hz.
            let f = 45 + 175 * expf(-t * 28)
            phase += 2 * .pi * f / sampleRate
            let thump = sinf(phase) * expf(-t * 18) * 0.9

            // Crack: high-passed noise, very fast decay.
            let white = rng.nextFloat()
            lp += 0.35 * (white - lp)
            let crack = (white - lp) * expf(-t * 90) * 1.4

            // Whoosh: band-passed noise with a swell.
            lp2 += 0.08 * (white - lp2)
            let whooshEnv = sinf(min(1, t / 0.32) * .pi) * expf(-t * 4)
            let whoosh = (lp2 - lp * 0.5) * whooshEnv * 1.2

            let s = (thump + crack + whoosh) * 1.6
            l[i] += s
            r[i] += s
        }
    }

    private func crackle(_ l: inout [Float], _ r: inout [Float], _ rng: inout SeededRandom) {
        for _ in 0..<70 {
            let start = 0.05 + powf(rng.nextUnit(), 1.6) * 1.1
            let amp = 0.12 + rng.nextUnit() * 0.25
            let pan = rng.nextUnit()
            let length = Int((0.002 + rng.nextUnit() * 0.004) * sampleRate)
            let startFrame = Int(start * sampleRate)
            var lp: Float = 0
            for i in 0..<length where startFrame + i < l.count {
                let white = rng.nextFloat()
                lp += 0.5 * (white - lp)
                let env = 1 - Float(i) / Float(length)
                let s = (white - lp * 0.6) * env * amp * expf(-start * 1.2)
                l[startFrame + i] += s * (1 - pan).squareRoot()
                r[startFrame + i] += s * pan.squareRoot()
            }
        }
    }

    private func sparkle(_ l: inout [Float], _ r: inout [Float]) {
        // Pentatonic run: C5 D5 E5 G5 A5 C6 D6 E6 G6 C7
        let notes: [Float] = [523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66, 1318.51, 1567.98, 2093]
        for (index, freq) in notes.enumerated() {
            let start = 0.12 + Float(index) * 0.058
            let decay: Float = index == notes.count - 1 ? 1.4 : 0.7
            let pan = Float(index) / Float(notes.count - 1)
            let amp: Float = 0.22 * (index == notes.count - 1 ? 1.3 : 1)
            let startFrame = Int(start * sampleRate)
            let length = Int(decay * 3 * sampleRate)
            for i in 0..<length where startFrame + i < l.count {
                let t = Float(i) / sampleRate
                // FM bell: modulator at 2x carrier, modulation index decays quickly.
                let modIndex = 2.2 * expf(-t * 6)
                let mod = sinf(2 * .pi * freq * 2 * t) * modIndex
                let tone = sinf(2 * .pi * freq * t + mod)
                let attack = min(1, t / 0.003)
                let s = tone * attack * expf(-t / decay) * amp
                l[startFrame + i] += s * (1 - pan * 0.8).squareRoot()
                r[startFrame + i] += s * (0.2 + pan * 0.8).squareRoot()
            }
        }
    }

    private func chord(_ l: inout [Float], _ r: inout [Float]) {
        // C3 root with a C major add9 voicing above: C4 E4 G4 D5
        let voices: [(freq: Float, amp: Float, pan: Float)] = [
            (130.81, 0.28, 0.5), (261.63, 0.24, 0.42), (329.63, 0.21, 0.58), (392.0, 0.21, 0.38), (587.33, 0.15, 0.62),
        ]
        let start: Float = 0.15
        let attack: Float = 0.12
        let hold: Float = 0.55
        let release: Float = 1.3
        let startFrame = Int(start * sampleRate)
        let length = Int((attack + hold + release) * sampleRate)

        for voice in voices {
            var phases: [Float] = [0, 0, 0]
            let detune: [Float] = [-0.4, 0, 0.4]   // percent
            var filtered: Float = 0
            var vibratoPhase: Float = 0
            for i in 0..<length where startFrame + i < l.count {
                let t = Float(i) / sampleRate
                let env: Float
                if t < attack { env = t / attack }
                else if t < attack + hold { env = 1 }
                else { env = expf(-(t - attack - hold) / (release * 0.35)) }

                vibratoPhase += 2 * .pi * 5.5 / sampleRate
                let vibrato = 1 + sinf(vibratoPhase) * 0.003 * min(1, t / 0.4)

                var saw: Float = 0
                for v in 0..<3 {
                    let f = voice.freq * (1 + detune[v] / 100) * vibrato
                    phases[v] += f / sampleRate
                    if phases[v] >= 1 { phases[v] -= 1 }
                    saw += (phases[v] * 2 - 1)
                }
                saw /= 3

                // Low-pass that opens on the attack and closes during the release.
                let cutoff = 500 + 3500 * env * expf(-t * 1.2)
                let a = 1 - expf(-2 * .pi * cutoff / sampleRate)
                filtered += a * (saw - filtered)

                let s = filtered * env * voice.amp
                l[startFrame + i] += s * (1 - voice.pan).squareRoot()
                r[startFrame + i] += s * voice.pan.squareRoot()
            }
        }
    }

    // MARK: - Effects

    /// Simple Schroeder reverb: four parallel feedback combs into two series all-pass filters.
    private func reverb(_ input: [Float], delayOffset: Int) -> [Float] {
        let combDelays = [1557, 1617, 1491, 1422].map { $0 + delayOffset }
        let combFeedback: Float = 0.76
        var combBuffers = combDelays.map { [Float](repeating: 0, count: $0) }
        var combLowpass = [Float](repeating: 0, count: combDelays.count)
        let allpassDelays = [225, 556].map { $0 + delayOffset / 3 }
        var allpassBuffers = allpassDelays.map { [Float](repeating: 0, count: $0) }

        var output = [Float](repeating: 0, count: input.count)
        for i in 0..<input.count {
            var sum: Float = 0
            for c in 0..<combDelays.count {
                let idx = i % combDelays[c]
                let delayed = combBuffers[c][idx]
                combLowpass[c] += 0.4 * (delayed - combLowpass[c])   // damp highs in the tail
                combBuffers[c][idx] = input[i] + combLowpass[c] * combFeedback
                sum += delayed
            }
            var s = sum / Float(combDelays.count)
            for a in 0..<allpassDelays.count {
                let idx = i % allpassDelays[a]
                let delayed = allpassBuffers[a][idx]
                let v = s + delayed * 0.5
                allpassBuffers[a][idx] = v
                s = delayed - v * 0.5
            }
            output[i] = s
        }
        return output
    }

    private func fadeOut(_ l: inout [Float], _ r: inout [Float], seconds: Float) {
        let n = min(l.count, Int(seconds * sampleRate))
        for i in 0..<n {
            let g = Float(n - i) / Float(n)
            l[l.count - n + i] *= g
            r[r.count - n + i] *= g
        }
    }

    private func normalizeAndLimit(_ l: inout [Float], _ r: inout [Float], peak: Float) {
        var maxAbs: Float = 0.0001
        for i in 0..<l.count { maxAbs = max(maxAbs, abs(l[i]), abs(r[i])) }
        let gain = peak / maxAbs * 1.25   // slight push into the soft clipper for glue
        for i in 0..<l.count {
            l[i] = tanhf(l[i] * gain) * peak
            r[i] = tanhf(r[i] * gain) * peak
        }
    }
}

/// Deterministic xorshift RNG so the sound is identical on every launch.
struct SeededRandom {
    private var state: UInt32
    init(seed: UInt32) { state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// Uniform in [-1, 1].
    mutating func nextFloat() -> Float { Float(next()) / Float(UInt32.max) * 2 - 1 }
    /// Uniform in [0, 1].
    mutating func nextUnit() -> Float { Float(next()) / Float(UInt32.max) }
}
