import Foundation

// MARK: - EQ Band

struct EQBand: Codable, Equatable, Sendable {
    var frequency: Float   // Hz (20...20000)
    var gain: Float        // dB (-12...+12)
    var bandwidth: Float   // octaves, default 1.0

    init(frequency: Float, gain: Float, bandwidth: Float = 1.0) {
        self.frequency = frequency
        self.gain = gain
        self.bandwidth = bandwidth
    }
}

// MARK: - EQ Preset Data

struct EQPresetData: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var bands: [EQBand]
    let isBuiltIn: Bool

    /// Automatic preamp reduction to prevent clipping.
    /// Uses half the max boost as a compromise between clipping prevention and volume.
    var preampGain: Float {
        let maxBoost = bands.map(\.gain).max() ?? 0
        return maxBoost > 0 ? -(maxBoost * 0.5) : 0
    }

    var isFlat: Bool {
        bands.allSatisfy { $0.gain == 0 }
    }
}

// MARK: - Constants

extension EQPresetData {
    static let defaultFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let maxBandCount = 31
    static let minBandCount = 1
}

// MARK: - Built-in Presets

extension EQPresetData {
    static let flat = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Flat",
        bands: defaultFrequencies.map { EQBand(frequency: $0, gain: 0) },
        isBuiltIn: true
    )

    static let bassBoost = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Bass Boost",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([10, 10,  8,  4,  0,  0,  0,  0,  0,  0]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let vocalClarity = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Vocal Clarity",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([-6, -6, -4,  0,  0,  6,  6,  4,  0,  0]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let builtInPresets: [EQPresetData] = [.flat, .bassBoost, .vocalClarity]

    /// Suggest a frequency for a new band inserted into the current set.
    /// Finds the largest gap (in octaves) between existing bands and returns
    /// the geometric midpoint.
    func suggestNewBandFrequency() -> Float {
        guard !bands.isEmpty else { return 1000 }
        let sorted = bands.map(\.frequency).sorted()

        // Check gap below lowest
        var bestFreq: Float = sorted[0] / 2
        var bestGap: Float = log2(sorted[0] / 20) // gap from 20 Hz

        // Check gaps between bands
        for i in 1..<sorted.count {
            let gap = log2(sorted[i] / sorted[i - 1])
            if gap > bestGap {
                bestGap = gap
                bestFreq = sqrt(sorted[i] * sorted[i - 1]) // geometric midpoint
            }
        }

        // Check gap above highest
        let topGap = log2(20000 / sorted.last!)
        if topGap > bestGap {
            bestFreq = sorted.last! * 2
        }

        return min(max(bestFreq, 20), 20000)
    }
}

// MARK: - Frequency Formatting

extension EQBand {
    var frequencyLabel: String {
        if frequency >= 1000 {
            let k = frequency / 1000
            if k == Float(Int(k)) {
                return "\(Int(k)) kHz"
            } else {
                return String(format: "%.1f kHz", k)
            }
        } else if frequency == Float(Int(frequency)) {
            return "\(Int(frequency)) Hz"
        } else {
            return String(format: "%.1f Hz", frequency)
        }
    }

    var gainLabel: String {
        if gain == 0 { return "0" }
        if gain == Float(Int(gain)) {
            return String(format: "%+d", Int(gain))
        }
        return String(format: "%+.1f", gain)
    }
}
