use super::ring_buffer::AudioRingBuffer;
use super::spectrum_data::{SpectrumData, BIN_COUNT};
use rustfft::{num_complex::Complex, FftPlanner};
use std::sync::Arc;

const FFT_SIZE: usize = 2048;
const HALF_N: usize = FFT_SIZE / 2;

/// Real-time FFT spectrum analyzer.
/// Reads audio data from a ring buffer, computes FFT, maps to log-frequency bins,
/// applies smoothing and peak hold, writes to SpectrumData for UI consumption.
pub struct SpectrumAnalyzer {
    pub spectrum_data: Arc<SpectrumData>,

    // FFT
    fft: Arc<dyn rustfft::Fft<f32>>,
    hann_window: Vec<f32>,
    bin_edge_frequencies: Vec<f32>,

    // Work buffers
    fft_input: Vec<Complex<f32>>,
    mono_buffer: Vec<f32>,
    db_mags: Vec<f32>,

    // Smoothing state
    smoothed: Vec<f32>,
    peaks: Vec<f32>,
    peak_hold_counters: Vec<i32>,

    // Constants
    decay_factor: f32,
    peak_hold_frames: i32,
    peak_fall_rate: f32,
    silence_threshold: f32,
}

impl SpectrumAnalyzer {
    pub fn new() -> Self {
        let mut planner = FftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FFT_SIZE);

        // Hann window
        let hann_window: Vec<f32> = (0..FFT_SIZE)
            .map(|i| {
                let t = i as f32 / FFT_SIZE as f32;
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * t).cos())
            })
            .collect();

        // Log-spaced bin edges (BIN_COUNT+1 edges, 20Hz to 20kHz)
        let bin_edge_frequencies: Vec<f32> = (0..=BIN_COUNT)
            .map(|i| {
                let t = i as f32 / BIN_COUNT as f32;
                20.0 * 1000.0_f32.powf(t)
            })
            .collect();

        Self {
            spectrum_data: Arc::new(SpectrumData::new()),
            fft,
            hann_window,
            bin_edge_frequencies,
            fft_input: vec![Complex::new(0.0, 0.0); FFT_SIZE],
            mono_buffer: vec![0.0; FFT_SIZE],
            db_mags: vec![0.0; HALF_N],
            smoothed: vec![-90.0; BIN_COUNT],
            peaks: vec![-90.0; BIN_COUNT],
            peak_hold_counters: vec![0; BIN_COUNT],
            decay_factor: 0.85,
            peak_hold_frames: 47,
            peak_fall_rate: 1.7,
            silence_threshold: -89.0,
        }
    }

    /// Process audio from the ring buffer. Call this periodically from the FFT thread.
    pub fn process_from_ring_buffer(&mut self, ring: &AudioRingBuffer, sample_rate: f64) {
        let available = ring.available_to_read();
        if available < FFT_SIZE {
            return;
        }

        // Read the most recent FFT_SIZE samples (skip older ones)
        if available > FFT_SIZE {
            let skip = available - FFT_SIZE;
            let mut discard = vec![0.0_f32; skip.min(4096)];
            let mut remaining = skip;
            while remaining > 0 {
                let chunk = remaining.min(discard.len());
                ring.read(&mut discard[..chunk]);
                remaining -= chunk;
            }
        }

        ring.read(&mut self.mono_buffer);
        self.compute_fft(sample_rate);
    }

    fn compute_fft(&mut self, sample_rate: f64) {
        // Apply Hann window and convert to complex
        for i in 0..FFT_SIZE {
            self.fft_input[i] = Complex::new(self.mono_buffer[i] * self.hann_window[i], 0.0);
        }

        // In-place FFT
        self.fft.process(&mut self.fft_input);

        // Compute magnitudes in dB
        let norm_factor = 1.0 / (HALF_N as f32 * HALF_N as f32);
        for i in 0..HALF_N {
            let c = self.fft_input[i];
            let mag_sq = (c.re * c.re + c.im * c.im) * norm_factor;
            self.db_mags[i] = 10.0 * (mag_sq + 1e-10).log10();
        }

        // Map to log-frequency bins, smooth, write to shared buffer
        self.map_to_log_bins(sample_rate);
    }

    fn map_to_log_bins(&mut self, sample_rate: f64) {
        let freq_per_bin = sample_rate as f32 / FFT_SIZE as f32;

        for i in 0..BIN_COUNT {
            let lo_freq = self.bin_edge_frequencies[i];
            let hi_freq = self.bin_edge_frequencies[i + 1];

            let lo_bin = (lo_freq / freq_per_bin) as usize;
            let hi_bin = ((hi_freq / freq_per_bin) as usize).min(HALF_N - 1);

            if lo_bin >= HALF_N {
                continue;
            }

            let raw = if lo_bin >= hi_bin {
                self.db_mags[lo_bin.min(HALF_N - 1)]
            } else {
                let sum: f32 = (lo_bin..=hi_bin).map(|b| self.db_mags[b]).sum();
                sum / (hi_bin - lo_bin + 1) as f32
            };
            let raw = raw.max(-90.0);

            // Smoothing: instant attack, exponential decay
            if raw > self.smoothed[i] {
                self.smoothed[i] = raw;
            } else {
                self.smoothed[i] =
                    self.smoothed[i] * self.decay_factor + raw * (1.0 - self.decay_factor);
            }

            if self.smoothed[i] < self.silence_threshold {
                self.smoothed[i] = -90.0;
            }

            // Peak hold
            if raw > self.peaks[i] {
                self.peaks[i] = raw;
                self.peak_hold_counters[i] = self.peak_hold_frames;
            } else if self.peak_hold_counters[i] > 0 {
                self.peak_hold_counters[i] -= 1;
            } else {
                self.peaks[i] -= self.peak_fall_rate;
                if self.peaks[i] < self.silence_threshold {
                    self.peaks[i] = -90.0;
                }
            }
        }

        self.spectrum_data.write(&self.smoothed, &self.peaks);
    }
}
