import Foundation

// MARK: - Normalized Biquad Coefficients

/// Pre-normalized biquad coefficients (divided by a0) for real-time processing.
struct NormalizedBiquadCoeffs: Sendable {
    let b0: Float, b1: Float, b2: Float
    let a1: Float, a2: Float

    init(from raw: BiquadCoefficients) {
        let a0 = Float(raw.a0)
        b0 = Float(raw.b0) / a0
        b1 = Float(raw.b1) / a0
        b2 = Float(raw.b2) / a0
        a1 = Float(raw.a1) / a0
        a2 = Float(raw.a2) / a0
    }

    static let passthrough = NormalizedBiquadCoeffs(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    private init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }
}

// MARK: - Biquad Filter Chain

/// Real-time biquad filter chain for per-channel EQ processing.
/// Maintains filter state (delay elements) per band.
/// Designed for use on the Core Audio IO thread — no allocations after setup.
final class BiquadFilterChain: @unchecked Sendable {
    /// Per-band coefficients.
    private var coeffs: [NormalizedBiquadCoeffs]
    /// Per-band delay state: z1, z2 (Direct Form II Transposed).
    private var z1: [Float]
    private var z2: [Float]
    private var bandCount: Int

    init(bands: [EQBand], sampleRate: Double) {
        bandCount = bands.count
        coeffs = bands.map { band in
            NormalizedBiquadCoeffs(from: BiquadResponse.coefficients(for: band, sampleRate: sampleRate))
        }
        z1 = [Float](repeating: 0, count: bandCount)
        z2 = [Float](repeating: 0, count: bandCount)
    }

    /// Update coefficients from new band parameters. Resets state if band count changed.
    func updateCoefficients(bands: [EQBand], sampleRate: Double) {
        let newCount = bands.count
        let newCoeffs = bands.map { band in
            NormalizedBiquadCoeffs(from: BiquadResponse.coefficients(for: band, sampleRate: sampleRate))
        }

        if newCount != bandCount {
            z1 = [Float](repeating: 0, count: newCount)
            z2 = [Float](repeating: 0, count: newCount)
            bandCount = newCount
        }

        coeffs = newCoeffs
    }

    /// Process audio samples in-place using Direct Form II Transposed.
    /// Called on the Core Audio IO thread.
    func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for b in 0..<bandCount {
            let c = coeffs[b]
            var s1 = z1[b]
            var s2 = z2[b]

            for f in 0..<frameCount {
                let x = buffer[f]
                let y = c.b0 * x + s1
                s1 = c.b1 * x - c.a1 * y + s2
                s2 = c.b2 * x - c.a2 * y
                buffer[f] = y
            }

            // Flush denormals to zero
            if abs(s1) < 1e-15 { s1 = 0 }
            if abs(s2) < 1e-15 { s2 = 0 }

            z1[b] = s1
            z2[b] = s2
        }
    }

    /// Reset all filter state (e.g., when switching presets to avoid transients).
    func reset() {
        for i in 0..<bandCount {
            z1[i] = 0
            z2[i] = 0
        }
    }
}
