//! Plays the party sound. Uses a user-supplied file if present at
//! ~/Library/Application Support/Finito/party.(wav|mp3|m4a|aiff|aif|caf), otherwise a freshly
//! composed one.
use crate::rng::SeededRandom;
use objc2::AllocAnyThread;
use objc2_avf_audio::AVAudioPlayer;
use objc2_foundation::{NSData, NSString, NSURL};
use std::f32::consts::PI;
use std::path::PathBuf;
use std::time::Duration;

const SAMPLE_RATE: f32 = 44_100.0;

/// Plays the sound for `seed` and returns once playback has finished.
pub fn play(seed: u32) {
    // SAFETY: AVAudioPlayer is self-contained; we keep it alive until playback is over.
    let player = unsafe {
        match custom_sound_path() {
            Some(path) => {
                let url = NSURL::fileURLWithPath(&NSString::from_str(&path.to_string_lossy()));
                AVAudioPlayer::initWithContentsOfURL_error(AVAudioPlayer::alloc(), &url)
            }
            None => {
                let wav = PartySoundSynth {
                    sample_rate: SAMPLE_RATE,
                    seed,
                }
                .render_wav();
                AVAudioPlayer::initWithData_error(AVAudioPlayer::alloc(), &NSData::with_bytes(&wav))
            }
        }
    };
    let player = match player {
        Ok(player) => player,
        Err(error) => {
            eprintln!("finito: could not load the party sound: {error}");
            return;
        }
    };
    // SAFETY: plain method calls on a live player.
    unsafe {
        player.prepareToPlay();
        if !player.play() {
            eprintln!("finito: could not play the party sound");
            return;
        }
        let duration = player.duration();
        std::thread::sleep(Duration::from_secs_f64(duration.max(0.0) + 0.1));
        // Belt and braces: wait out any tail the duration did not account for.
        while player.isPlaying() {
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}

fn custom_sound_path() -> Option<PathBuf> {
    let home = std::env::var_os("HOME")?;
    let dir = PathBuf::from(home).join("Library/Application Support/Finito");
    ["wav", "mp3", "m4a", "aiff", "aif", "caf"]
        .iter()
        .map(|ext| dir.join(format!("party.{ext}")))
        .find(|path| path.is_file())
}

/// Composes and renders a short party jingle from a seed, so every launch sounds a little different
/// while staying in key and in harmony.
///
/// Structure (times vary with the seed):
///   0.00  paper crackle as the leaves stream out
///   0.10  a soft "approach" chord (IV, V or ii) under the start of the run
///   0.12  melodic run: a pentatonic pattern in a random key, bell timbre, panned across the field
///   ~0.9  the run lands on the tonic: a bell chord (add9, maj7, maj9 or 6/9) with a warm pad
///   after that, high plinks in key sprinkled around like the last leaves floating down
/// Everything runs through a small stereo Schroeder reverb and a soft limiter.
struct PartySoundSynth {
    sample_rate: f32,
    seed: u32,
}

const PENTATONIC: [i32; 5] = [0, 2, 4, 7, 9];

#[derive(Clone, Copy)]
struct Timbre {
    ratio: f32,      // FM modulator ratio
    index: f32,      // FM modulation depth
    decay: f32,      // seconds
    brightness: f32, // extra sine partial an octave up, 0...1
}

/// A run is a list of pentatonic scale indices (5 per octave) and a beat length per note.
struct Pattern {
    degrees: &'static [i32],
    beats: Option<&'static [f32]>,
}

const PATTERNS: &[Pattern] = &[
    Pattern {
        degrees: &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        beats: None,
    }, // straight run
    Pattern {
        degrees: &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        beats: None,
    }, // long run
    Pattern {
        degrees: &[0, 2, 3, 5, 7, 8, 10, 12],
        beats: None,
    }, // chord-tone arpeggio
    Pattern {
        degrees: &[0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 8, 7, 10],
        beats: None,
    }, // zig-zag, up two down one
    Pattern {
        degrees: &[0, 3, 2, 5, 4, 7, 6, 9, 8, 10],
        beats: None,
    }, // bouncing thirds
    Pattern {
        degrees: &[0, 0, 3, 5, 5, 7, 10],
        beats: Some(&[1.0, 1.0, 2.0, 2.0, 1.0, 1.0, 2.0]),
    }, // fanfare
    Pattern {
        degrees: &[0, 2, 4, 7, 9, 12, 9, 10],
        beats: Some(&[1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0]),
    }, // up and a turn
    Pattern {
        degrees: &[0, 5, 2, 7, 3, 8, 5, 10],
        beats: None,
    }, // leaping octaves
    Pattern {
        degrees: &[2, 3, 5, 7, 8, 10, 12],
        beats: Some(&[1.0; 7]),
    }, // starting on the third
];

/// Intervals above the key's root an octave down. All resolve nicely to the tonic.
const APPROACH_CHORDS: &[&[i32]] = &[
    &[5, 9, 12, 14],  // IV add9
    &[7, 11, 14, 17], // V7
    &[2, 5, 9, 12],   // ii
    &[5, 9, 12, 16],  // IV maj7
];

const TONIC_VOICINGS: &[&[i32]] = &[
    &[0, 4, 7, 14],     // add9
    &[0, 4, 7, 11],     // maj7
    &[0, 4, 7, 11, 14], // maj9
    &[0, 4, 7, 9, 14],  // 6/9
    &[0, 7, 11, 16],    // open maj7
];

fn semitones(pentatonic_index: i32) -> i32 {
    (pentatonic_index / 5) * 12 + PENTATONIC[(pentatonic_index % 5) as usize]
}

fn freq(midi: i32) -> f32 {
    440.0 * 2f32.powf((midi - 69) as f32 / 12.0)
}

impl PartySoundSynth {
    /// Renders the jingle as a 16-bit stereo WAV file in memory.
    fn render_wav(&self) -> Vec<u8> {
        let (left, right) = self.render();
        let frames = left.len();
        let data_len = (frames * 4) as u32;
        let mut wav = Vec::with_capacity(44 + data_len as usize);
        wav.extend_from_slice(b"RIFF");
        wav.extend_from_slice(&(36 + data_len).to_le_bytes());
        wav.extend_from_slice(b"WAVEfmt ");
        wav.extend_from_slice(&16u32.to_le_bytes()); // chunk size
        wav.extend_from_slice(&1u16.to_le_bytes()); // PCM
        wav.extend_from_slice(&2u16.to_le_bytes()); // channels
        wav.extend_from_slice(&(self.sample_rate as u32).to_le_bytes());
        wav.extend_from_slice(&(self.sample_rate as u32 * 4).to_le_bytes()); // bytes per second
        wav.extend_from_slice(&4u16.to_le_bytes()); // block align
        wav.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
        wav.extend_from_slice(b"data");
        wav.extend_from_slice(&data_len.to_le_bytes());
        for i in 0..frames {
            for sample in [left[i], right[i]] {
                let s = (sample.clamp(-1.0, 1.0) * 32767.0).round() as i16;
                wav.extend_from_slice(&s.to_le_bytes());
            }
        }
        wav
    }

    fn render(&self) -> (Vec<f32>, Vec<f32>) {
        let sr = self.sample_rate;
        let mut rng = SeededRandom::new(self.seed);

        // Key and pattern.
        let root_midi = 72 + (rng.next_unit() * 7.99) as i32; // C5 ... G5
        let pattern = &PATTERNS[rng.index(PATTERNS.len())];
        let step = 0.052 + rng.next_unit() * 0.04; // seconds per beat of the run
        let swing = 0.9 + rng.next_unit() * 0.2;
        let pan_left_to_right = rng.next_unit() < 0.5;
        let timbre = Timbre {
            ratio: [1.5, 2.0, 2.0, 3.0, 3.5][(rng.next_unit() * 4.99) as usize],
            index: 1.2 + rng.next_unit() * 1.6,
            decay: 0.55 + rng.next_unit() * 0.35,
            brightness: rng.next_unit() * 0.5,
        };

        // Timeline of the run.
        let run_start: f32 = 0.12;
        let mut note_times: Vec<f32> = Vec::new();
        let mut t = run_start;
        for i in 0..pattern.degrees.len() {
            let beats = pattern.beats.map(|b| b[i]).unwrap_or(1.0);
            note_times.push(t);
            t += step * beats * if i % 2 == 0 { swing } else { 2.0 - swing };
        }
        let landing = t; // when the tonic chord hits
        let total = landing + 2.3;
        let frames = (total * sr) as usize;
        let mut left = vec![0f32; frames];
        let mut right = vec![0f32; frames];

        let crackles = 50 + (rng.next_unit() * 40.0) as usize;
        self.crackle(&mut left, &mut right, &mut rng, crackles, landing);

        // Approach chord: soft, under the run, resolving on the landing.
        let approach = APPROACH_CHORDS[rng.index(APPROACH_CHORDS.len())];
        for (i, interval) in approach.iter().enumerate() {
            let midi = root_midi - 12 + interval;
            let pan = 0.35 + 0.3 * i as f32 / (approach.len() - 1) as f32;
            self.pad(
                &mut left,
                &mut right,
                freq(midi),
                0.1,
                (landing - 0.25).max(0.1),
                0.25,
                0.055,
                pan,
                1400.0,
            );
        }

        // Melodic run.
        for (i, &degree) in pattern.degrees.iter().enumerate() {
            let midi = root_midi + semitones(degree);
            let progress = i as f32 / (pattern.degrees.len() - 1).max(1) as f32;
            let pan = if pan_left_to_right {
                0.15 + 0.7 * progress
            } else {
                0.85 - 0.7 * progress
            };
            let last = i == pattern.degrees.len() - 1;
            let decay = if last { timbre.decay * 2.2 } else { timbre.decay };
            let amp = 0.2 * if last { 1.25 } else { 1.0 } * (0.9 + 0.2 * rng.next_unit());
            self.bell(
                &mut left,
                &mut right,
                freq(midi),
                note_times[i],
                timbre,
                decay,
                amp,
                pan,
            );
        }

        // Tonic chord on the landing: bells plus a warm pad.
        let voicing = TONIC_VOICINGS[rng.index(TONIC_VOICINGS.len())];
        for (i, interval) in voicing.iter().enumerate() {
            let midi = root_midi - 12 + interval;
            let pan = 0.3 + 0.4 * i as f32 / (voicing.len() - 1) as f32;
            let chord_timbre = Timbre {
                ratio: 2.0,
                index: 0.9,
                decay: 1.5,
                brightness: 0.2,
            };
            self.bell(&mut left, &mut right, freq(midi), landing, chord_timbre, 1.5, 0.13, pan);
            self.pad(
                &mut left,
                &mut right,
                freq(midi),
                landing,
                0.7,
                0.5,
                0.07,
                1.0 - pan,
                1800.0,
            );
        }
        self.pad(
            &mut left,
            &mut right,
            freq(root_midi - 24),
            landing,
            0.7,
            0.5,
            0.09,
            0.5,
            600.0,
        );

        // Floating plinks: high notes from the scale, sprinkled after the landing.
        let plinks = 5 + (rng.next_unit() * 7.0) as usize;
        for _ in 0..plinks {
            let degree = (rng.next_unit() * 4.99) as usize;
            let midi = root_midi + 12 + PENTATONIC[degree] + if rng.next_unit() < 0.4 { 12 } else { 0 };
            let start = landing + 0.15 + rng.next_unit().powf(1.3) * 1.3;
            let decay = 0.5 + rng.next_unit() * 0.3;
            let amp = 0.07 + rng.next_unit() * 0.07;
            let pan = rng.next_unit();
            self.bell(&mut left, &mut right, freq(midi), start, timbre, decay, amp, pan);
        }

        let wet_l = self.reverb(&left, 0);
        let wet_r = self.reverb(&right, 31);
        for i in 0..frames {
            left[i] = left[i] * 0.78 + wet_l[i] * 0.3;
            right[i] = right[i] * 0.78 + wet_r[i] * 0.3;
        }
        self.fade_out(&mut left, &mut right, 0.25);
        normalize_and_limit(&mut left, &mut right, 0.85);
        (left, right)
    }

    // MARK: - Voices

    #[allow(clippy::too_many_arguments)]
    fn bell(
        &self,
        l: &mut [f32],
        r: &mut [f32],
        freq: f32,
        start: f32,
        timbre: Timbre,
        decay: f32,
        amp: f32,
        pan: f32,
    ) {
        let sr = self.sample_rate;
        let start_frame = (start * sr) as usize;
        let length = (decay * 3.5 * sr) as usize;
        let (gl, gr) = ((1.0 - pan * 0.8).sqrt(), (0.2 + pan * 0.8).sqrt());
        for i in 0..length {
            let Some(frame) = start_frame.checked_add(i).filter(|&f| f < l.len()) else {
                break;
            };
            let t = i as f32 / sr;
            let mod_index = timbre.index * (-t * 6.0).exp();
            let modulator = (2.0 * PI * freq * timbre.ratio * t).sin() * mod_index;
            let mut tone = (2.0 * PI * freq * t + modulator).sin();
            tone += (2.0 * PI * freq * 2.0 * t).sin() * timbre.brightness * (-t * 9.0).exp();
            let s = tone * (t / 0.003).min(1.0) * (-t / decay).exp() * amp;
            l[frame] += s * gl;
            r[frame] += s * gr;
        }
    }

    /// Three detuned saws through a gentle low-pass: warmth under the bells.
    #[allow(clippy::too_many_arguments)]
    fn pad(
        &self,
        l: &mut [f32],
        r: &mut [f32],
        freq: f32,
        start: f32,
        hold: f32,
        release: f32,
        amp: f32,
        pan: f32,
        cutoff: f32,
    ) {
        let sr = self.sample_rate;
        let attack: f32 = 0.08;
        let start_frame = (start * sr) as usize;
        let length = ((attack + hold + release * 3.0) * sr) as usize;
        let mut phases = [0f32; 3];
        let detune = [-0.5f32, 0.0, 0.5];
        let mut filtered: f32 = 0.0;
        let (gl, gr) = ((1.0 - pan).sqrt(), pan.sqrt());
        for i in 0..length {
            let Some(frame) = start_frame.checked_add(i).filter(|&f| f < l.len()) else {
                break;
            };
            let t = i as f32 / sr;
            let env = if t < attack {
                t / attack
            } else if t < attack + hold {
                1.0
            } else {
                (-(t - attack - hold) / release).exp()
            };
            let mut saw: f32 = 0.0;
            for v in 0..3 {
                phases[v] += freq * (1.0 + detune[v] / 100.0) / sr;
                if phases[v] >= 1.0 {
                    phases[v] -= 1.0;
                }
                saw += phases[v] * 2.0 - 1.0;
            }
            let a = 1.0 - (-2.0 * PI * cutoff * (0.5 + 0.5 * env) / sr).exp();
            filtered += a * (saw / 3.0 - filtered);
            let s = filtered * env * amp;
            l[frame] += s * gl;
            r[frame] += s * gr;
        }
    }

    fn crackle(&self, l: &mut [f32], r: &mut [f32], rng: &mut SeededRandom, count: usize, end: f32) {
        let sr = self.sample_rate;
        for _ in 0..count {
            let start = 0.03 + rng.next_unit().powf(1.6) * end;
            let amp = 0.12 + rng.next_unit() * 0.25;
            let pan = rng.next_unit();
            let length = ((0.002 + rng.next_unit() * 0.004) * sr) as usize;
            let start_frame = (start * sr) as usize;
            let mut lp: f32 = 0.0;
            for i in 0..length {
                let Some(frame) = start_frame.checked_add(i).filter(|&f| f < l.len()) else {
                    break;
                };
                let white = rng.next_float();
                lp += 0.5 * (white - lp);
                let env = 1.0 - i as f32 / length as f32;
                let s = (white - lp * 0.6) * env * amp * (-start * 1.2).exp();
                l[frame] += s * (1.0 - pan).sqrt();
                r[frame] += s * pan.sqrt();
            }
        }
    }

    // MARK: - Effects

    /// Simple Schroeder reverb: four parallel feedback combs into two series all-pass filters.
    fn reverb(&self, input: &[f32], delay_offset: usize) -> Vec<f32> {
        let comb_delays: Vec<usize> = [1557, 1617, 1491, 1422].iter().map(|d| d + delay_offset).collect();
        let comb_feedback: f32 = 0.78;
        let mut comb_buffers: Vec<Vec<f32>> = comb_delays.iter().map(|&d| vec![0.0; d]).collect();
        let mut comb_lowpass = vec![0f32; comb_delays.len()];
        let allpass_delays: Vec<usize> = [225, 556].iter().map(|d| d + delay_offset / 3).collect();
        let mut allpass_buffers: Vec<Vec<f32>> = allpass_delays.iter().map(|&d| vec![0.0; d]).collect();

        let mut output = vec![0f32; input.len()];
        for (i, &x) in input.iter().enumerate() {
            let mut sum: f32 = 0.0;
            for c in 0..comb_delays.len() {
                let idx = i % comb_delays[c];
                let delayed = comb_buffers[c][idx];
                comb_lowpass[c] += 0.4 * (delayed - comb_lowpass[c]); // damp highs in the tail
                comb_buffers[c][idx] = x + comb_lowpass[c] * comb_feedback;
                sum += delayed;
            }
            let mut s = sum / comb_delays.len() as f32;
            for a in 0..allpass_delays.len() {
                let idx = i % allpass_delays[a];
                let delayed = allpass_buffers[a][idx];
                let v = s + delayed * 0.5;
                allpass_buffers[a][idx] = v;
                s = delayed - v * 0.5;
            }
            output[i] = s;
        }
        output
    }

    fn fade_out(&self, l: &mut [f32], r: &mut [f32], seconds: f32) {
        let n = l.len().min((seconds * self.sample_rate) as usize);
        let total = l.len();
        for i in 0..n {
            let g = (n - i) as f32 / n as f32;
            l[total - n + i] *= g;
            r[total - n + i] *= g;
        }
    }
}

fn normalize_and_limit(l: &mut [f32], r: &mut [f32], peak: f32) {
    let mut max_abs: f32 = 0.0001;
    for i in 0..l.len() {
        max_abs = max_abs.max(l[i].abs()).max(r[i].abs());
    }
    let gain = peak / max_abs * 1.2; // slight push into the soft clipper for glue
    for i in 0..l.len() {
        l[i] = (l[i] * gain).tanh() * peak;
        r[i] = (r[i] * gain).tanh() * peak;
    }
}
