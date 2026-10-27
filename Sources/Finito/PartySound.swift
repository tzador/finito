import AVFoundation
import AppKit

/// Plays the party sound. Uses a user-supplied file if present at
/// ~/Library/Application Support/Finito/party.(wav|mp3|m4a|aiff), otherwise a freshly composed one.
final class PartySound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var customSound: NSSound?

    init(seed: UInt32) {
        customSound = Self.loadCustomSound()
        guard customSound == nil else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffer = PartySoundSynth(sampleRate: Float(format.sampleRate), seed: seed).render(into: format)
    }

    /// Plays the sound; `completion` runs on the main queue once playback has finished.
    func play(completion: (() -> Void)? = nil) {
        if let customSound {
            customSound.stop()
            customSound.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + customSound.duration + 0.1) { completion?() }
            return
        }
        guard let buffer else { completion?(); return }
        do {
            if !engine.isRunning { try engine.start() }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { _ in
                DispatchQueue.main.async { completion?() }
            }
            player.play()
        } catch {
            NSLog("Audio engine failed: \(error)")
            completion?()
        }
    }

    private static func loadCustomSound() -> NSSound? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("Finito")
        for ext in ["wav", "mp3", "m4a", "aiff", "aif", "caf"] {
            let url = dir.appendingPathComponent("party.\(ext)")
            if FileManager.default.fileExists(atPath: url.path), let sound = NSSound(contentsOf: url, byReference: false) {
                return sound
            }
        }
        return nil
    }
}

/// Composes and renders a short party jingle from a seed, so every launch sounds a little different
/// while staying in key and in harmony.
///
/// Structure (times vary with the seed):
///   0.00  paper crackle as the confetti streams out
///   0.10  a soft "approach" chord (IV, V or ii) under the start of the run
///   0.12  melodic run: a pentatonic pattern in a random key, bell timbre, panned across the field
///   ~0.9  the run lands on the tonic: a bell chord (add9, maj7, maj9 or 6/9) with a warm pad
///   after that, high plinks in key sprinkled around like the last pieces floating down
/// Everything runs through a small stereo Schroeder reverb and a soft limiter.
struct PartySoundSynth {
    let sampleRate: Float
    let seed: UInt32

    private static let pentatonic = [0, 2, 4, 7, 9]

    private struct Timbre {
        let ratio: Float        // FM modulator ratio
        let index: Float        // FM modulation depth
        let decay: Float        // seconds
        let brightness: Float   // extra sine partial an octave up, 0...1
    }

    func render(into format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var rng = SeededRandom(seed: seed)

        // Key and pattern.
        let rootMidi = 72 + Int(rng.nextUnit() * 7.99)            // C5 ... G5
        let pattern = Self.patterns[Int(rng.nextUnit() * Float(Self.patterns.count) * 0.999)]
        let step = 0.052 + rng.nextUnit() * 0.04                   // seconds per beat of the run
        let swing = 0.9 + rng.nextUnit() * 0.2
        let panLeftToRight = rng.nextUnit() < 0.5
        let timbre = Timbre(
            ratio: [1.5, 2, 2, 3, 3.5][Int(rng.nextUnit() * 4.99)],
            index: 1.2 + rng.nextUnit() * 1.6,
            decay: 0.55 + rng.nextUnit() * 0.35,
            brightness: rng.nextUnit() * 0.5
        )

        // Timeline of the run.
        var runStart: Float = 0.12
        var noteTimes: [Float] = []
        var t = runStart
        for (i, beats) in pattern.beats.enumerated() {
            noteTimes.append(t)
            t += step * beats * (i % 2 == 0 ? swing : 2 - swing)
        }
        let landing = t                                             // when the tonic chord hits
        let total = landing + 2.3
        let frames = Int(total * sampleRate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)

        crackle(&left, &right, &rng, count: 50 + Int(rng.nextUnit() * 40), until: landing)

        // Approach chord: soft, under the run, resolving on the landing.
        let approach = Self.approachChords[Int(rng.nextUnit() * Float(Self.approachChords.count) * 0.999)]
        for (i, interval) in approach.enumerated() {
            let midi = rootMidi - 12 + interval
            pad(&left, &right, freq: Self.freq(midi), start: 0.1, hold: max(0.1, landing - 0.25), release: 0.25,
                amp: 0.055, pan: 0.35 + 0.3 * Float(i) / Float(approach.count - 1), cutoff: 1400)
        }

        // Melodic run.
        runStart = noteTimes.first ?? runStart
        for (i, degree) in pattern.degrees.enumerated() {
            let midi = rootMidi + Self.semitones(forPentatonicIndex: degree)
            let progress = Float(i) / Float(max(1, pattern.degrees.count - 1))
            let pan = panLeftToRight ? 0.15 + 0.7 * progress : 0.85 - 0.7 * progress
            let last = i == pattern.degrees.count - 1
            bell(&left, &right, freq: Self.freq(midi), start: noteTimes[i], timbre: timbre,
                 decay: last ? timbre.decay * 2.2 : timbre.decay, amp: 0.2 * (last ? 1.25 : 1) * (0.9 + 0.2 * rng.nextUnit()), pan: pan)
        }

        // Tonic chord on the landing: bells plus a warm pad.
        let voicing = Self.tonicVoicings[Int(rng.nextUnit() * Float(Self.tonicVoicings.count) * 0.999)]
        for (i, interval) in voicing.enumerated() {
            let midi = rootMidi - 12 + interval
            let pan = 0.3 + 0.4 * Float(i) / Float(voicing.count - 1)
            bell(&left, &right, freq: Self.freq(midi), start: landing, timbre: Timbre(ratio: 2, index: 0.9, decay: 1.5, brightness: 0.2),
                 decay: 1.5, amp: 0.13, pan: pan)
            pad(&left, &right, freq: Self.freq(midi), start: landing, hold: 0.7, release: 0.5, amp: 0.07, pan: 1 - pan, cutoff: 1800)
        }
        pad(&left, &right, freq: Self.freq(rootMidi - 24), start: landing, hold: 0.7, release: 0.5, amp: 0.09, pan: 0.5, cutoff: 600)

        // Floating plinks: high notes from the scale, sprinkled after the landing.
        let plinks = 5 + Int(rng.nextUnit() * 7)
        for _ in 0..<plinks {
            let degree = Int(rng.nextUnit() * 4.99)
            let midi = rootMidi + 12 + Self.pentatonic[degree] + (rng.nextUnit() < 0.4 ? 12 : 0)
            let start = landing + 0.15 + powf(rng.nextUnit(), 1.3) * 1.3
            bell(&left, &right, freq: Self.freq(midi), start: start, timbre: timbre, decay: 0.5 + rng.nextUnit() * 0.3,
                 amp: 0.07 + rng.nextUnit() * 0.07, pan: rng.nextUnit())
        }

        let wetL = reverb(left, delayOffset: 0)
        let wetR = reverb(right, delayOffset: 31)
        for i in 0..<frames {
            left[i] = left[i] * 0.78 + wetL[i] * 0.3
            right[i] = right[i] * 0.78 + wetR[i] * 0.3
        }
        fadeOut(&left, &right, seconds: 0.25)
        normalizeAndLimit(&left, &right, peak: 0.85)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: frames) }
        right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: frames) }
        return buffer
    }

    // MARK: - Music

    /// A run is a list of pentatonic scale indices (5 per octave) and a beat length per note.
    private struct Pattern {
        let degrees: [Int]
        let beats: [Float]
        init(_ degrees: [Int], beats: [Float]? = nil) {
            self.degrees = degrees
            self.beats = beats ?? [Float](repeating: 1, count: degrees.count)
        }
    }

    private static let patterns: [Pattern] = [
        Pattern([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]),                                 // straight run
        Pattern([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),                     // long run
        Pattern([0, 2, 3, 5, 7, 8, 10, 12]),                                     // chord-tone arpeggio
        Pattern([0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 8, 7, 10]),              // zig-zag, up two down one
        Pattern([0, 3, 2, 5, 4, 7, 6, 9, 8, 10]),                                // bouncing thirds
        Pattern([0, 0, 3, 5, 5, 7, 10], beats: [1, 1, 2, 2, 1, 1, 2]),           // fanfare
        Pattern([0, 2, 4, 7, 9, 12, 9, 10], beats: [1, 1, 1, 1, 1, 2, 1, 1]),    // up and a turn
        Pattern([0, 5, 2, 7, 3, 8, 5, 10]),                                      // leaping octaves
        Pattern([2, 3, 5, 7, 8, 10, 12], beats: [1, 1, 1, 1, 1, 1, 1]),          // starting on the third
    ]

    /// Intervals above the key's root an octave down. All resolve nicely to the tonic.
    private static let approachChords: [[Int]] = [
        [5, 9, 12, 14],       // IV add9
        [7, 11, 14, 17],      // V7
        [2, 5, 9, 12],        // ii
        [5, 9, 12, 16],       // IV maj7
    ]

    private static let tonicVoicings: [[Int]] = [
        [0, 4, 7, 14],        // add9
        [0, 4, 7, 11],        // maj7
        [0, 4, 7, 11, 14],    // maj9
        [0, 4, 7, 9, 14],     // 6/9
        [0, 7, 11, 16],       // open maj7
    ]

    private static func semitones(forPentatonicIndex index: Int) -> Int {
        (index / 5) * 12 + pentatonic[index % 5]
    }

    private static func freq(_ midi: Int) -> Float {
        440 * powf(2, Float(midi - 69) / 12)
    }

    // MARK: - Voices

    private func bell(_ l: inout [Float], _ r: inout [Float], freq: Float, start: Float, timbre: Timbre, decay: Float, amp: Float, pan: Float) {
        let startFrame = Int(start * sampleRate)
        let length = Int(decay * 3.5 * sampleRate)
        let gl = (1 - pan * 0.8).squareRoot(), gr = (0.2 + pan * 0.8).squareRoot()
        for i in 0..<length where startFrame + i < l.count {
            let t = Float(i) / sampleRate
            let modIndex = timbre.index * expf(-t * 6)
            let mod = sinf(2 * .pi * freq * timbre.ratio * t) * modIndex
            var tone = sinf(2 * .pi * freq * t + mod)
            tone += sinf(2 * .pi * freq * 2.0 * t) * timbre.brightness * expf(-t * 9)
            let s = tone * min(1, t / 0.003) * expf(-t / decay) * amp
            l[startFrame + i] += s * gl
            r[startFrame + i] += s * gr
        }
    }

    /// Three detuned saws through a gentle low-pass: warmth under the bells.
    private func pad(_ l: inout [Float], _ r: inout [Float], freq: Float, start: Float, hold: Float, release: Float, amp: Float, pan: Float, cutoff: Float) {
        let attack: Float = 0.08
        let startFrame = Int(start * sampleRate)
        let length = Int((attack + hold + release * 3) * sampleRate)
        var phases: [Float] = [0, 0, 0]
        let detune: [Float] = [-0.5, 0, 0.5]
        var filtered: Float = 0
        let gl = (1 - pan).squareRoot(), gr = pan.squareRoot()
        for i in 0..<length where startFrame + i < l.count {
            let t = Float(i) / sampleRate
            let env: Float
            if t < attack { env = t / attack }
            else if t < attack + hold { env = 1 }
            else { env = expf(-(t - attack - hold) / release) }
            var saw: Float = 0
            for v in 0..<3 {
                phases[v] += freq * (1 + detune[v] / 100) / sampleRate
                if phases[v] >= 1 { phases[v] -= 1 }
                saw += phases[v] * 2 - 1
            }
            let a = 1 - expf(-2 * .pi * cutoff * (0.5 + 0.5 * env) / sampleRate)
            filtered += a * (saw / 3 - filtered)
            let s = filtered * env * amp
            l[startFrame + i] += s * gl
            r[startFrame + i] += s * gr
        }
    }

    private func crackle(_ l: inout [Float], _ r: inout [Float], _ rng: inout SeededRandom, count: Int, until end: Float) {
        for _ in 0..<count {
            let start = 0.03 + powf(rng.nextUnit(), 1.6) * end
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

    // MARK: - Effects

    /// Simple Schroeder reverb: four parallel feedback combs into two series all-pass filters.
    private func reverb(_ input: [Float], delayOffset: Int) -> [Float] {
        let combDelays = [1557, 1617, 1491, 1422].map { $0 + delayOffset }
        let combFeedback: Float = 0.78
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
        let gain = peak / maxAbs * 1.2   // slight push into the soft clipper for glue
        for i in 0..<l.count {
            l[i] = tanhf(l[i] * gain) * peak
            r[i] = tanhf(r[i] * gain) * peak
        }
    }
}

/// Deterministic xorshift RNG so a given seed always composes the same jingle.
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
