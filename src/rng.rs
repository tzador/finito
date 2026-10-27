/// Deterministic xorshift RNG so a given seed always composes the same show and jingle.
#[derive(Clone)]
pub struct SeededRandom {
    state: u32,
}

impl SeededRandom {
    pub fn new(seed: u32) -> Self {
        Self {
            state: if seed == 0 { 1 } else { seed },
        }
    }

    pub fn next(&mut self) -> u32 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 17;
        self.state ^= self.state << 5;
        self.state
    }

    /// Uniform in [-1, 1].
    pub fn next_float(&mut self) -> f32 {
        self.next() as f32 / u32::MAX as f32 * 2.0 - 1.0
    }

    /// Uniform in [0, 1].
    pub fn next_unit(&mut self) -> f32 {
        self.next() as f32 / u32::MAX as f32
    }

    /// Uniform in [lo, hi].
    pub fn range(&mut self, lo: f32, hi: f32) -> f32 {
        lo + (hi - lo) * self.next_unit()
    }

    pub fn chance(&mut self, probability: f32) -> bool {
        self.next_unit() < probability
    }

    /// Uniform index in 0..count.
    pub fn index(&mut self, count: usize) -> usize {
        ((self.next_unit() * count as f32 * 0.999) as usize).min(count.saturating_sub(1))
    }
}
