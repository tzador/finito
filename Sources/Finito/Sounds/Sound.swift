import Foundation

/// Every built-in sound finito can play. All of them are synthesized at launch.
enum Sound: String, CaseIterable {
    case party, fanfare, tada, chime, coin, powerup, applause, drumroll, pop, sparkle, whoosh
    case none

    static var audible: [Sound] { allCases.filter { $0 != .none } }

    /// Renders the sound into a stereo buffer at `sampleRate`.
    func render(sampleRate: Float) -> Mixer {
        switch self {
        case .party: return SoundRecipes.party(sampleRate)
        case .fanfare: return SoundRecipes.fanfare(sampleRate)
        case .tada: return SoundRecipes.tada(sampleRate)
        case .chime: return SoundRecipes.chime(sampleRate)
        case .coin: return SoundRecipes.coin(sampleRate)
        case .powerup: return SoundRecipes.powerup(sampleRate)
        case .applause: return SoundRecipes.applause(sampleRate)
        case .drumroll: return SoundRecipes.drumroll(sampleRate)
        case .pop: return SoundRecipes.pop(sampleRate)
        case .sparkle: return SoundRecipes.sparkle(sampleRate)
        case .whoosh: return SoundRecipes.whoosh(sampleRate)
        case .none: return Mixer(seconds: 0.01, sampleRate: sampleRate, seed: 1)
        }
    }
}

enum SoundRecipes {
    private static let pentatonic: [Float] = [523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66, 1318.51, 1567.98, 2093]

    /// Paper crackle as the confetti streams out, then an ascending bell glissando.
    static func party(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 2.8, sampleRate: sr, seed: 0xC0FFEE)
        addCrackle(&m)
        addSparkle(&m, start: 0.12)
        m.finish(reverb: 0.28)
        return m
    }

    static func sparkle(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 3.0, sampleRate: sr, seed: 0x59A)
        addSparkle(&m, start: 0.02)
        m.finish(reverb: 0.4)
        return m
    }

    private static func addCrackle(_ m: inout Mixer) {
        for _ in 0..<70 {
            let start = 0.05 + powf(m.rng.nextUnit(), 1.6) * 1.1
            let amp = (0.12 + m.rng.nextUnit() * 0.25) * expf(-start * 1.2)
            let pan = m.rng.nextUnit()
            let length = 0.002 + m.rng.nextUnit() * 0.004
            m.noise(start: start, duration: length, pan: pan, amp: amp, q: 0.7, mode: .high, centre: { _ in 3000 }) { t in 1 - t / length }
        }
    }

    private static func addSparkle(_ m: inout Mixer, start: Float) {
        for (index, freq) in pentatonic.enumerated() {
            let last = index == pentatonic.count - 1
            m.bell(start: start + Float(index) * 0.058, frequency: freq, decay: last ? 1.4 : 0.7,
                   amp: 0.22 * (last ? 1.3 : 1), pan: 0.1 + 0.8 * Float(index) / Float(pentatonic.count - 1))
        }
    }

    /// Three ascending brass notes and a held chord with a sub bass.
    static func fanfare(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 2.6, sampleRate: sr, seed: 0xFA)
        let notes: [(Float, Float)] = [(392.0, 0.0), (523.25, 0.2), (659.25, 0.4)]
        for (freq, start) in notes {
            m.brass(start: start, frequency: freq, attack: 0.02, hold: 0.14, release: 0.08, amp: 0.3, brightness: 5000)
        }
        for (freq, pan) in [(783.99, 0.6), (523.25, 0.4), (659.25, 0.55), (392.0, 0.45), (130.81, 0.5)] as [(Float, Float)] {
            m.brass(start: 0.6, frequency: freq, attack: 0.03, hold: 0.7, release: 0.35, amp: freq < 200 ? 0.3 : 0.22, pan: pan, brightness: 4500)
        }
        m.finish(reverb: 0.3)
        return m
    }

    /// The classic "ta-daa": a short pickup chord, then a bright major chord with a cymbal.
    static func tada(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 2.4, sampleRate: sr, seed: 0x7ADA)
        for freq in [392.0, 493.88, 587.33] as [Float] {
            m.brass(start: 0, frequency: freq, attack: 0.01, hold: 0.1, release: 0.05, amp: 0.25, brightness: 5000)
        }
        for (freq, pan) in [(523.25, 0.4), (659.25, 0.6), (783.99, 0.45), (1046.5, 0.55), (261.63, 0.5)] as [(Float, Float)] {
            m.brass(start: 0.22, frequency: freq, attack: 0.02, hold: 0.9, release: 0.4, amp: 0.22, pan: pan, brightness: 5500)
        }
        m.noise(start: 0.22, duration: 1.4, amp: 0.35, q: 0.6, mode: .high, centre: { _ in 6000 }) { t in expf(-t * 3.2) }
        m.finish(reverb: 0.35)
        return m
    }

    /// Wind-chime arpeggio with long sine partial tails.
    static func chime(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 3.6, sampleRate: sr, seed: 0xC41E)
        let notes: [Float] = [659.25, 783.99, 987.77, 1318.51, 1975.53, 1318.51]
        for (i, freq) in notes.enumerated() {
            let pan = 0.2 + 0.6 * Float(i % 3) / 2
            m.bell(start: Float(i) * 0.17, frequency: freq, decay: 1.6, amp: 0.2, pan: pan, ratio: 3.01, index: 1.2)
            m.bell(start: Float(i) * 0.17, frequency: freq * 2.76, decay: 0.5, amp: 0.05, pan: 1 - pan, ratio: 1.0, index: 0)
        }
        m.finish(reverb: 0.45)
        return m
    }

    /// 8-bit coin: a square blip that jumps up a fourth.
    static func coin(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 0.9, sampleRate: sr, seed: 0xC01)
        m.tone(start: 0, duration: 0.085, amp: 0.25, frequency: { _ in 987.77 }, wave: Mixer.square) { t in min(1, t / 0.002) }
        m.tone(start: 0.085, duration: 0.6, amp: 0.25, frequency: { _ in 1318.51 }, wave: Mixer.square) { t in expf(-t * 7) }
        m.finish(reverb: 0.08)
        return m
    }

    /// Rising stepped sweep on a crushed square wave.
    static func powerup(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 1.1, sampleRate: sr, seed: 0x90)
        let sweep: Float = 0.75
        m.tone(start: 0, duration: sweep + 0.3, amp: 0.25, frequency: { t in
            let steps = floorf(min(t, sweep) / 0.045)
            return 220 * powf(2, steps * 0.045 / sweep * 3.2)
        }, wave: { p in floorf(Mixer.square(p) * 0.5 + Mixer.triangle(p) * 0.5 * 6) / 6 }) { t in
            t < sweep ? min(1, t / 0.01) : expf(-(t - sweep) * 9)
        }
        m.finish(reverb: 0.15)
        return m
    }

    /// A crowd clapping: hundreds of short noise bursts whose density swells and dies away.
    static func applause(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 3.4, sampleRate: sr, seed: 0xA99)
        let total: Float = 3.4
        func density(_ t: Float) -> Float {
            if t < 0.5 { return t / 0.5 }
            if t < 2.0 { return 1 }
            return max(0, 1 - (t - 2.0) / 1.2)
        }
        for _ in 0..<520 {
            let t = m.rng.nextUnit() * total
            guard m.rng.nextUnit() < density(t) else { continue }
            let centre = 1200 + m.rng.nextUnit() * 2200
            let amp = 0.15 + m.rng.nextUnit() * 0.2
            m.noise(start: t, duration: 0.012, pan: m.rng.nextUnit(), amp: amp, q: 1.4, mode: .band, centre: { _ in centre }) { u in expf(-u * 250) }
        }
        m.noise(start: 0, duration: total, amp: 0.08, q: 0.7, mode: .low, centre: { _ in 1800 }) { t in density(t) }
        m.finish(reverb: 0.35)
        return m
    }

    /// Accelerating snare taps ending in a crash.
    static func drumroll(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 3.0, sampleRate: sr, seed: 0xD2)
        var t: Float = 0
        var interval: Float = 0.11
        var count = 0
        while t < 1.7 {
            let amp = 0.3 + Float(count % 2) * 0.1 + t * 0.15
            m.noise(start: t, duration: 0.03, pan: 0.5 + (count % 2 == 0 ? -0.1 : 0.1), amp: amp, q: 0.8, mode: .band, centre: { _ in 1800 }) { u in expf(-u * 120) }
            m.tone(start: t, duration: 0.03, amp: 0.4, frequency: { u in 190 - u * 1500 }) { u in expf(-u * 90) }
            t += interval
            interval = max(0.028, interval * 0.93)
            count += 1
        }
        m.tone(start: 1.72, duration: 0.3, amp: 0.6, frequency: { u in 60 + 120 * expf(-u * 30) }) { u in expf(-u * 10) }
        m.noise(start: 1.72, duration: 1.2, amp: 0.5, q: 0.5, mode: .high, centre: { _ in 5000 }) { u in min(1, u / 0.01) * expf(-u * 2.8) }
        m.finish(reverb: 0.3)
        return m
    }

    /// A handful of bubble pops: short pitched blips with a resonant drop.
    static func pop(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 1.8, sampleRate: sr, seed: 0x9090)
        for i in 0..<8 {
            let start = Float(i) * 0.17 + m.rng.nextUnit() * 0.08
            let base = 500 + m.rng.nextUnit() * 700
            let up = m.rng.nextUnit() < 0.35
            m.tone(start: start, duration: 0.09, pan: m.rng.nextUnit(), amp: 0.3, frequency: { t in
                up ? base * (1 + t * 12) : base * expf(-t * 25) + 180
            }) { t in expf(-t * 45) * min(1, t / 0.001) }
            m.noise(start: start, duration: 0.01, amp: 0.15, q: 2, mode: .band, centre: { _ in base * 2 }) { t in expf(-t * 400) }
        }
        m.finish(reverb: 0.25)
        return m
    }

    /// Band-passed noise sweeping up and across the stereo field.
    static func whoosh(_ sr: Float) -> Mixer {
        var m = Mixer(seconds: 1.5, sampleRate: sr, seed: 0x3003)
        let length: Float = 1.2
        for (pan, lag) in [(0.15, 0.0), (0.85, 0.12)] as [(Float, Float)] {
            m.noise(start: lag, duration: length, pan: pan, amp: 0.5, q: 2.5, mode: .band, centre: { t in 150 * powf(2, t / length * 5) }) { t in
                powf(sinf(.pi * t / length), 1.5)
            }
        }
        m.finish(reverb: 0.2)
        return m
    }
}
