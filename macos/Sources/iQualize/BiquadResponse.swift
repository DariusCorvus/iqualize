import Foundation

// MARK: - Biquad Coefficients

struct BiquadCoefficients: Sendable {
    let b0: Double, b1: Double, b2: Double
    let a0: Double, a1: Double, a2: Double

    /// Evaluate the filter's gain in dB at a given frequency.
    func gainDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2.0 * .pi * frequency / sampleRate
        let cosW = cos(w), sinW = sin(w)
        let cos2W = cos(2.0 * w), sin2W = sin(2.0 * w)

        // Normalize by a0
        let nb0 = b0 / a0, nb1 = b1 / a0, nb2 = b2 / a0
        let na1 = a1 / a0, na2 = a2 / a0

        let numReal = nb0 + nb1 * cosW + nb2 * cos2W
        let numImag = -(nb1 * sinW + nb2 * sin2W)
        let denReal = 1.0 + na1 * cosW + na2 * cos2W
        let denImag = -(na1 * sinW + na2 * sin2W)

        let numMagSq = numReal * numReal + numImag * numImag
        let denMagSq = denReal * denReal + denImag * denImag

        guard denMagSq > 1e-30 else { return -120.0 }
        return 10.0 * log10(numMagSq / denMagSq)
    }
}

// MARK: - Biquad Response Computation

enum BiquadResponse {

    /// Generate log-spaced frequencies from 20 Hz to 20 kHz.
    static func logFrequencies(count: Int = 512) -> [Double] {
        (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            return 20.0 * pow(1000.0, t)
        }
    }

    /// Compute biquad coefficients for a band using Audio EQ Cookbook formulas.
    static func coefficients(for band: EQBand, sampleRate: Double) -> BiquadCoefficients {
        let f0 = Double(band.frequency)
        let gain = Double(band.gain)
        let bw = Double(max(band.bandwidth, 0.05))

        let w0 = 2.0 * .pi * f0 / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)

        // Bandwidth (octaves) → Q conversion
        let sinW0Safe = abs(sinW0) > 1e-10 ? sinW0 : 1e-10
        let Q = 1.0 / (2.0 * sinh(log(2.0) / 2.0 * bw * w0 / sinW0Safe))

        let alpha = sinW0 / (2.0 * Q)

        switch band.filterType {
        case .parametric:
            let A = pow(10.0, gain / 40.0)
            return BiquadCoefficients(
                b0: 1.0 + alpha * A,
                b1: -2.0 * cosW0,
                b2: 1.0 - alpha * A,
                a0: 1.0 + alpha / A,
                a1: -2.0 * cosW0,
                a2: 1.0 - alpha / A
            )

        case .lowShelf:
            let A = pow(10.0, gain / 40.0)
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            return BiquadCoefficients(
                b0: A * ((A + 1) - (A - 1) * cosW0 + twoSqrtAAlpha),
                b1: 2.0 * A * ((A - 1) - (A + 1) * cosW0),
                b2: A * ((A + 1) - (A - 1) * cosW0 - twoSqrtAAlpha),
                a0: (A + 1) + (A - 1) * cosW0 + twoSqrtAAlpha,
                a1: -2.0 * ((A - 1) + (A + 1) * cosW0),
                a2: (A + 1) + (A - 1) * cosW0 - twoSqrtAAlpha
            )

        case .highShelf:
            let A = pow(10.0, gain / 40.0)
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            return BiquadCoefficients(
                b0: A * ((A + 1) + (A - 1) * cosW0 + twoSqrtAAlpha),
                b1: -2.0 * A * ((A - 1) + (A + 1) * cosW0),
                b2: A * ((A + 1) + (A - 1) * cosW0 - twoSqrtAAlpha),
                a0: (A + 1) - (A - 1) * cosW0 + twoSqrtAAlpha,
                a1: 2.0 * ((A - 1) - (A + 1) * cosW0),
                a2: (A + 1) - (A - 1) * cosW0 - twoSqrtAAlpha
            )

        case .lowPass:
            return BiquadCoefficients(
                b0: (1.0 - cosW0) / 2.0,
                b1: 1.0 - cosW0,
                b2: (1.0 - cosW0) / 2.0,
                a0: 1.0 + alpha,
                a1: -2.0 * cosW0,
                a2: 1.0 - alpha
            )

        case .highPass:
            return BiquadCoefficients(
                b0: (1.0 + cosW0) / 2.0,
                b1: -(1.0 + cosW0),
                b2: (1.0 + cosW0) / 2.0,
                a0: 1.0 + alpha,
                a1: -2.0 * cosW0,
                a2: 1.0 - alpha
            )

        case .bandPass:
            return BiquadCoefficients(
                b0: alpha,
                b1: 0.0,
                b2: -alpha,
                a0: 1.0 + alpha,
                a1: -2.0 * cosW0,
                a2: 1.0 - alpha
            )

        case .notch:
            return BiquadCoefficients(
                b0: 1.0,
                b1: -2.0 * cosW0,
                b2: 1.0,
                a0: 1.0 + alpha,
                a1: -2.0 * cosW0,
                a2: 1.0 - alpha
            )
        }
    }

    /// Composite frequency response: sum of all bands' dB contributions.
    static func compositeResponse(
        bands: [EQBand], sampleRate: Double, frequencies: [Double]
    ) -> [Double] {
        guard !bands.isEmpty else {
            return [Double](repeating: 0.0, count: frequencies.count)
        }

        let allCoeffs = bands.map { coefficients(for: $0, sampleRate: sampleRate) }
        return frequencies.map { freq in
            var total = 0.0
            for coeffs in allCoeffs {
                total += coeffs.gainDB(at: freq, sampleRate: sampleRate)
            }
            return total
        }
    }
}
