use serde::{Deserialize, Serialize};
use std::f64::consts::PI;

// -- Filter Type --

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FilterType {
    Parametric,
    LowShelf,
    HighShelf,
    LowPass,
    HighPass,
    BandPass,
    Notch,
}

impl FilterType {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Parametric => "Bell",
            Self::LowShelf => "Lo Shelf",
            Self::HighShelf => "Hi Shelf",
            Self::LowPass => "Lo Pass",
            Self::HighPass => "Hi Pass",
            Self::BandPass => "Band Pass",
            Self::Notch => "Notch",
        }
    }
}

// -- EQ Band --

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct EQBand {
    pub frequency: f32,
    pub gain: f32,
    #[serde(default = "default_bandwidth")]
    pub bandwidth: f32,
    #[serde(default)]
    pub filter_type: FilterType,
}

fn default_bandwidth() -> f32 {
    1.0
}

impl Default for FilterType {
    fn default() -> Self {
        Self::Parametric
    }
}

impl EQBand {
    pub fn new(frequency: f32, gain: f32) -> Self {
        Self {
            frequency,
            gain,
            bandwidth: 1.0,
            filter_type: FilterType::Parametric,
        }
    }

    pub fn with_bandwidth(mut self, bw: f32) -> Self {
        self.bandwidth = bw;
        self
    }

    pub fn with_filter_type(mut self, ft: FilterType) -> Self {
        self.filter_type = ft;
        self
    }

    pub fn octaves_to_q(bw: f32) -> f32 {
        let p = 2.0_f32.powf(bw);
        p.sqrt() / (p - 1.0)
    }

    pub fn q_to_octaves(q: f32) -> f32 {
        2.0 * (1.0 / (2.0 * q)).asinh() / 2.0_f32.ln()
    }
}

// -- Raw Biquad Coefficients (f64 for computation) --

#[derive(Debug, Clone, Copy)]
pub struct BiquadCoefficients {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a0: f64,
    pub a1: f64,
    pub a2: f64,
}

impl BiquadCoefficients {
    /// Evaluate the filter's gain in dB at a given frequency.
    pub fn gain_db(&self, frequency: f64, sample_rate: f64) -> f64 {
        let w = 2.0 * PI * frequency / sample_rate;
        let cos_w = w.cos();
        let sin_w = w.sin();
        let cos_2w = (2.0 * w).cos();
        let sin_2w = (2.0 * w).sin();

        let nb0 = self.b0 / self.a0;
        let nb1 = self.b1 / self.a0;
        let nb2 = self.b2 / self.a0;
        let na1 = self.a1 / self.a0;
        let na2 = self.a2 / self.a0;

        let num_real = nb0 + nb1 * cos_w + nb2 * cos_2w;
        let num_imag = -(nb1 * sin_w + nb2 * sin_2w);
        let den_real = 1.0 + na1 * cos_w + na2 * cos_2w;
        let den_imag = -(na1 * sin_w + na2 * sin_2w);

        let num_mag_sq = num_real * num_real + num_imag * num_imag;
        let den_mag_sq = den_real * den_real + den_imag * den_imag;

        if den_mag_sq < 1e-30 {
            return -120.0;
        }
        10.0 * (num_mag_sq / den_mag_sq).log10()
    }

    /// Compute biquad coefficients for a band using Audio EQ Cookbook formulas.
    pub fn from_band(band: &EQBand, sample_rate: f64) -> Self {
        let f0 = band.frequency as f64;
        let gain = band.gain as f64;
        let bw = (band.bandwidth as f64).max(0.05);

        let w0 = 2.0 * PI * f0 / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();

        let sin_w0_safe = if sin_w0.abs() > 1e-10 { sin_w0 } else { 1e-10 };
        let q = 1.0 / (2.0 * ((2.0_f64.ln()) / 2.0 * bw * w0 / sin_w0_safe).sinh());
        let alpha = sin_w0 / (2.0 * q);

        match band.filter_type {
            FilterType::Parametric => {
                let a = 10.0_f64.powf(gain / 40.0);
                BiquadCoefficients {
                    b0: 1.0 + alpha * a,
                    b1: -2.0 * cos_w0,
                    b2: 1.0 - alpha * a,
                    a0: 1.0 + alpha / a,
                    a1: -2.0 * cos_w0,
                    a2: 1.0 - alpha / a,
                }
            }
            FilterType::LowShelf => {
                let a = 10.0_f64.powf(gain / 40.0);
                let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
                BiquadCoefficients {
                    b0: a * ((a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha),
                    b1: 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w0),
                    b2: a * ((a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha),
                    a0: (a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha,
                    a1: -2.0 * ((a - 1.0) + (a + 1.0) * cos_w0),
                    a2: (a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha,
                }
            }
            FilterType::HighShelf => {
                let a = 10.0_f64.powf(gain / 40.0);
                let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
                BiquadCoefficients {
                    b0: a * ((a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha),
                    b1: -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0),
                    b2: a * ((a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha),
                    a0: (a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha,
                    a1: 2.0 * ((a - 1.0) - (a + 1.0) * cos_w0),
                    a2: (a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha,
                }
            }
            FilterType::LowPass => BiquadCoefficients {
                b0: (1.0 - cos_w0) / 2.0,
                b1: 1.0 - cos_w0,
                b2: (1.0 - cos_w0) / 2.0,
                a0: 1.0 + alpha,
                a1: -2.0 * cos_w0,
                a2: 1.0 - alpha,
            },
            FilterType::HighPass => BiquadCoefficients {
                b0: (1.0 + cos_w0) / 2.0,
                b1: -(1.0 + cos_w0),
                b2: (1.0 + cos_w0) / 2.0,
                a0: 1.0 + alpha,
                a1: -2.0 * cos_w0,
                a2: 1.0 - alpha,
            },
            FilterType::BandPass => BiquadCoefficients {
                b0: alpha,
                b1: 0.0,
                b2: -alpha,
                a0: 1.0 + alpha,
                a1: -2.0 * cos_w0,
                a2: 1.0 - alpha,
            },
            FilterType::Notch => BiquadCoefficients {
                b0: 1.0,
                b1: -2.0 * cos_w0,
                b2: 1.0,
                a0: 1.0 + alpha,
                a1: -2.0 * cos_w0,
                a2: 1.0 - alpha,
            },
        }
    }
}

// -- Normalized Coefficients (f32 for real-time processing) --

#[derive(Debug, Clone, Copy)]
pub struct NormalizedCoeffs {
    pub b0: f32,
    pub b1: f32,
    pub b2: f32,
    pub a1: f32,
    pub a2: f32,
}

impl NormalizedCoeffs {
    pub fn from_raw(raw: &BiquadCoefficients) -> Self {
        let a0 = raw.a0 as f32;
        Self {
            b0: (raw.b0 as f32) / a0,
            b1: (raw.b1 as f32) / a0,
            b2: (raw.b2 as f32) / a0,
            a1: (raw.a1 as f32) / a0,
            a2: (raw.a2 as f32) / a0,
        }
    }

    pub fn passthrough() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
        }
    }
}

// -- Biquad Filter Chain --

/// Real-time biquad filter chain for per-channel EQ processing.
/// Uses Direct Form II Transposed. No allocations after setup.
pub struct BiquadFilterChain {
    coeffs: Vec<NormalizedCoeffs>,
    z1: Vec<f32>,
    z2: Vec<f32>,
    band_count: usize,
}

impl BiquadFilterChain {
    pub fn new(bands: &[EQBand], sample_rate: f64) -> Self {
        let band_count = bands.len();
        let coeffs: Vec<NormalizedCoeffs> = bands
            .iter()
            .map(|band| NormalizedCoeffs::from_raw(&BiquadCoefficients::from_band(band, sample_rate)))
            .collect();
        Self {
            coeffs,
            z1: vec![0.0; band_count],
            z2: vec![0.0; band_count],
            band_count,
        }
    }

    pub fn update_coefficients(&mut self, bands: &[EQBand], sample_rate: f64) {
        let new_count = bands.len();
        let new_coeffs: Vec<NormalizedCoeffs> = bands
            .iter()
            .map(|band| NormalizedCoeffs::from_raw(&BiquadCoefficients::from_band(band, sample_rate)))
            .collect();

        if new_count != self.band_count {
            self.z1 = vec![0.0; new_count];
            self.z2 = vec![0.0; new_count];
            self.band_count = new_count;
        }
        self.coeffs = new_coeffs;
    }

    /// Process audio samples in-place using Direct Form II Transposed.
    pub fn process(&mut self, buffer: &mut [f32]) {
        for b in 0..self.band_count {
            let c = self.coeffs[b];
            let mut s1 = self.z1[b];
            let mut s2 = self.z2[b];

            for sample in buffer.iter_mut() {
                let x = *sample;
                let y = c.b0 * x + s1;
                s1 = c.b1 * x - c.a1 * y + s2;
                s2 = c.b2 * x - c.a2 * y;
                *sample = y;
            }

            // Flush denormals to zero
            if s1.abs() < 1e-15 {
                s1 = 0.0;
            }
            if s2.abs() < 1e-15 {
                s2 = 0.0;
            }

            self.z1[b] = s1;
            self.z2[b] = s2;
        }
    }

    pub fn reset(&mut self) {
        for i in 0..self.band_count {
            self.z1[i] = 0.0;
            self.z2[i] = 0.0;
        }
    }
}

// -- Frequency response computation for UI --

/// Generate log-spaced frequencies from 20 Hz to 20 kHz.
pub fn log_frequencies(count: usize) -> Vec<f64> {
    (0..count)
        .map(|i| {
            let t = i as f64 / (count - 1) as f64;
            20.0 * 1000.0_f64.powf(t)
        })
        .collect()
}

/// Composite frequency response: sum of all bands' dB contributions.
pub fn composite_response(bands: &[EQBand], sample_rate: f64, frequencies: &[f64]) -> Vec<f64> {
    if bands.is_empty() {
        return vec![0.0; frequencies.len()];
    }

    let all_coeffs: Vec<BiquadCoefficients> = bands
        .iter()
        .map(|band| BiquadCoefficients::from_band(band, sample_rate))
        .collect();

    frequencies
        .iter()
        .map(|&freq| {
            all_coeffs
                .iter()
                .map(|coeffs| coeffs.gain_db(freq, sample_rate))
                .sum()
        })
        .collect()
}
