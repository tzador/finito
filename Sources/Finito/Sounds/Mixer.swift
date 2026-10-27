import Foundation

/// A stereo float buffer plus the small set of DSP building blocks the sound recipes are made of.
struct Mixer {
    let sampleRate: Float
    var left: [Float]
    var right: [Float]
    var rng: SeededRandom

    init(seconds: Float, sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        let frames = Int(seconds * sampleRate)
        left = [Float](repeating: 0, count: frames)
        right = [Float](repeating: 0, count: frames)
        rng = SeededRandom(seed: seed)
    }

    var frames: Int { left.count }

    // MARK: - Waveforms (phase in 0..<1)

    static func sine(_ p: Float) -> Float { sinf(2 * .pi * p) }
    static func square(_ p: Float) -> Float { p < 0.5 ? 1 : -1 }
    static func saw(_ p: Float) -> Float { p * 2 - 1 }
    static func triangle(_ p: Float) -> Float { 1 - 4 * abs(p - 0.5) }

    // MARK: - Envelopes

    /// Exponential decay with a short linear attack.
    static func pluck(_ t: Float, attack: Float = 0.003, decay: Float) -> Float {
        min(1, t / attack) * expf(-t / decay)
    }

    /// Attack, hold, then exponential release.
    static func ahr(_ t: Float, attack: Float, hold: Float, release: Float) -> Float {
        if t < attack { return t / attack }
        if t < attack + hold { return 1 }
        return expf(-(t - attack - hold) / release)
    }

    // MARK: - Voices

    /// Adds a tone whose frequency, waveform and amplitude envelope are given as functions of time.
    mutating func tone(
        start: Float, duration: Float, pan: Float = 0.5, amp: Float,
        frequency: (Float) -> Float, wave: (Float) -> Float = Mixer.sine, envelope: (Float) -> Float
    ) {
        let startFrame = Int(start * sampleRate)
        let length = Int(duration * sampleRate)
        var phase: Float = 0
        let gl = (1 - pan).squareRoot(), gr = pan.squareRoot()
        for i in 0..<length where startFrame + i < frames {
            let t = Float(i) / sampleRate
            phase += frequency(t) / sampleRate
            if phase >= 1 { phase -= 1 }
            let s = wave(phase) * envelope(t) * amp
            left[startFrame + i] += s * gl
            right[startFrame + i] += s * gr
        }
    }

    /// FM bell: a sine carrier modulated by a sine at `ratio` times its frequency, modulation fading quickly.
    mutating func bell(start: Float, frequency: Float, decay: Float, amp: Float, pan: Float = 0.5, ratio: Float = 2, index: Float = 2.2) {
        let startFrame = Int(start * sampleRate)
        let length = Int(decay * 3.5 * sampleRate)
        let gl = (1 - pan).squareRoot(), gr = pan.squareRoot()
        for i in 0..<length where startFrame + i < frames {
            let t = Float(i) / sampleRate
            let mod = sinf(2 * .pi * frequency * ratio * t) * index * expf(-t * 6)
            let s = sinf(2 * .pi * frequency * t + mod) * Mixer.pluck(t, decay: decay) * amp
            left[startFrame + i] += s * gl
            right[startFrame + i] += s * gr
        }
    }

    /// Three detuned saws through a low-pass that opens on the attack: a soft brass / synth pad.
    mutating func brass(start: Float, frequency: Float, attack: Float, hold: Float, release: Float, amp: Float, pan: Float = 0.5, brightness: Float = 3500) {
        let startFrame = Int(start * sampleRate)
        let length = Int((attack + hold + release * 3) * sampleRate)
        var phases: [Float] = [0, 0, 0]
        let detune: [Float] = [-0.4, 0, 0.4]
        var filtered: Float = 0
        var vibratoPhase: Float = 0
        let gl = (1 - pan).squareRoot(), gr = pan.squareRoot()
        for i in 0..<length where startFrame + i < frames {
            let t = Float(i) / sampleRate
            let env = Mixer.ahr(t, attack: attack, hold: hold, release: release)
            vibratoPhase += 2 * .pi * 5.5 / sampleRate
            let vibrato = 1 + sinf(vibratoPhase) * 0.003 * min(1, t / 0.4)
            var saw: Float = 0
            for v in 0..<3 {
                phases[v] += frequency * (1 + detune[v] / 100) * vibrato / sampleRate
                if phases[v] >= 1 { phases[v] -= 1 }
                saw += phases[v] * 2 - 1
            }
            saw /= 3
            let cutoff = 500 + brightness * env * expf(-t * 1.2)
            let a = 1 - expf(-2 * .pi * cutoff / sampleRate)
            filtered += a * (saw - filtered)
            let s = filtered * env * amp
            left[startFrame + i] += s * gl
            right[startFrame + i] += s * gr
        }
    }

    /// Noise burst through a state-variable filter. `centre` and `envelope` are functions of time.
    mutating func noise(
        start: Float, duration: Float, pan: Float = 0.5, amp: Float, q: Float = 1.0,
        mode: FilterMode, centre: (Float) -> Float, envelope: (Float) -> Float
    ) {
        let startFrame = Int(start * sampleRate)
        let length = Int(duration * sampleRate)
        var filter = StateVariableFilter()
        let gl = (1 - pan).squareRoot(), gr = pan.squareRoot()
        for i in 0..<length where startFrame + i < frames {
            let t = Float(i) / sampleRate
            let out = filter.process(rng.nextFloat(), cutoff: centre(t), q: q, sampleRate: sampleRate)
            let s = out[mode]! * envelope(t) * amp
            left[startFrame + i] += s * gl
            right[startFrame + i] += s * gr
        }
    }

    // MARK: - Mastering

    mutating func finish(reverb mix: Float, fadeOut: Float = 0.2, peak: Float = 0.85) {
        if mix > 0 {
            let wetL = Mixer.reverb(left, delayOffset: 0)
            let wetR = Mixer.reverb(right, delayOffset: 31)
            for i in 0..<frames {
                left[i] = left[i] * (1 - mix * 0.4) + wetL[i] * mix
                right[i] = right[i] * (1 - mix * 0.4) + wetR[i] * mix
            }
        }
        let n = min(frames, Int(fadeOut * sampleRate))
        for i in 0..<n {
            let g = Float(n - i) / Float(n)
            left[frames - n + i] *= g
            right[frames - n + i] *= g
        }
        var maxAbs: Float = 0.0001
        for i in 0..<frames { maxAbs = max(maxAbs, abs(left[i]), abs(right[i])) }
        let gain = peak / maxAbs * 1.25   // slight push into the soft clipper for glue
        for i in 0..<frames {
            left[i] = tanhf(left[i] * gain) * peak
            right[i] = tanhf(right[i] * gain) * peak
        }
    }

    /// Simple Schroeder reverb: four parallel feedback combs into two series all-pass filters.
    private static func reverb(_ input: [Float], delayOffset: Int) -> [Float] {
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
                combLowpass[c] += 0.4 * (delayed - combLowpass[c])
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
}

enum FilterMode { case low, band, high }

/// Chamberlin state-variable filter.
struct StateVariableFilter {
    private var low: Float = 0
    private var band: Float = 0

    mutating func process(_ input: Float, cutoff: Float, q: Float, sampleRate: Float) -> [FilterMode: Float] {
        let f = 2 * sinf(.pi * min(cutoff, sampleRate / 6) / sampleRate)
        let damp = 1 / max(0.5, q)
        low += f * band
        let high = input - low - damp * band
        band += f * high
        return [.low: low, .band: band, .high: high]
    }
}

/// Deterministic xorshift RNG so each sound is identical on every launch.
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
