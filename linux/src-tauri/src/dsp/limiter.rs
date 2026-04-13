/// Simple peak limiter using envelope following with attack/release.
/// Prevents digital clipping at 0 dBFS.
pub struct PeakLimiter {
    attack_coeff: f32,
    release_coeff: f32,
    envelope: f32,
    threshold: f32,
}

impl PeakLimiter {
    pub fn new(sample_rate: f64) -> Self {
        let attack_ms = 7.0;
        let release_ms = 24.0;
        Self {
            attack_coeff: (-1.0 / (attack_ms * 0.001 * sample_rate as f32)).exp(),
            release_coeff: (-1.0 / (release_ms * 0.001 * sample_rate as f32)).exp(),
            envelope: 0.0,
            threshold: 1.0, // 0 dBFS
        }
    }

    pub fn update_sample_rate(&mut self, sample_rate: f64) {
        let attack_ms = 7.0;
        let release_ms = 24.0;
        self.attack_coeff = (-1.0 / (attack_ms * 0.001 * sample_rate as f32)).exp();
        self.release_coeff = (-1.0 / (release_ms * 0.001 * sample_rate as f32)).exp();
    }

    /// Process a buffer of interleaved stereo samples in-place.
    pub fn process_stereo(&mut self, left: &mut [f32], right: &mut [f32]) {
        let len = left.len().min(right.len());
        for i in 0..len {
            let peak = left[i].abs().max(right[i].abs());

            // Envelope follower
            let coeff = if peak > self.envelope {
                self.attack_coeff
            } else {
                self.release_coeff
            };
            self.envelope = coeff * self.envelope + (1.0 - coeff) * peak;

            // Gain reduction
            if self.envelope > self.threshold {
                let gain = self.threshold / self.envelope;
                left[i] *= gain;
                right[i] *= gain;
            }
        }
    }

    pub fn reset(&mut self) {
        self.envelope = 0.0;
    }
}
