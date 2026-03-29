import AVFAudio
import Foundation

// MARK: - Filter Type

enum FilterType: String, Codable, CaseIterable, Equatable, Sendable {
    case parametric
    case lowShelf
    case highShelf
    case lowPass
    case highPass
    case bandPass
    case notch

    var displayName: String {
        switch self {
        case .parametric: return "Bell"
        case .lowShelf:   return "Lo Shelf"
        case .highShelf:  return "Hi Shelf"
        case .lowPass:    return "Lo Pass"
        case .highPass:   return "Hi Pass"
        case .bandPass:   return "Band Pass"
        case .notch:      return "Notch"
        }
    }

    var avType: AVAudioUnitEQFilterType {
        switch self {
        case .parametric: return .parametric
        case .lowShelf:   return .lowShelf
        case .highShelf:  return .highShelf
        case .lowPass:    return .lowPass
        case .highPass:   return .highPass
        case .bandPass:   return .bandPass
        case .notch:      return .bandStop
        }
    }
}

// MARK: - EQ Band

struct EQBand: Codable, Equatable, Sendable {
    var frequency: Float   // Hz (20...20000)
    var gain: Float        // dB (-12...+12)
    var bandwidth: Float   // octaves, default 1.0
    var filterType: FilterType

    init(frequency: Float, gain: Float, bandwidth: Float = 1.0, filterType: FilterType = .parametric) {
        self.frequency = frequency
        self.gain = gain
        self.bandwidth = bandwidth
        self.filterType = filterType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(Float.self, forKey: .frequency)
        gain = try container.decode(Float.self, forKey: .gain)
        bandwidth = try container.decode(Float.self, forKey: .bandwidth)
        filterType = try container.decodeIfPresent(FilterType.self, forKey: .filterType) ?? .parametric
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
        bands.allSatisfy { $0.gain == 0 && $0.filterType == .parametric }
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

    static let loudness = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Loudness",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([ 8,  6,  0, -2, -4, -2,  0,  2,  4,  6]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let trebleBoost = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Treble Boost",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([ 0,  0,  0,  0,  0,  2,  4,  6,  8, 10]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let podcast = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "Podcast",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([-8, -4, -2,  0,  2,  4,  6,  4,  2,  0]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let techno = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
        name: "Techno",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([ 8,  8,  4, -2, -4, -2,  0,  4,  6,  8]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let deepHouse = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
        name: "Deep House",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([ 6, 10,  8,  2, -2, -4, -2,  0,  2,  4]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let hardTechno = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
        name: "Hard Techno",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([10, 10,  6,  0, -4, -2,  2,  6,  8, 10]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let minimal = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
        name: "Minimal",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([ 4,  6,  4,  0, -2, -2,  0,  2,  4,  2]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let americanRap = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
        name: "American Rap",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([10,  8,  4,  0, -2, -2,  2,  4,  6,  4]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let germanRap = EQPresetData(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
        name: "German Rap",
        //                                        32  64 125 250 500  1k  2k  4k  8k 16k
        bands: zip(defaultFrequencies, [Float]([ 6,  8,  6,  2, -2,  0,  4,  4,  2,  2]))
            .map { EQBand(frequency: $0.0, gain: $0.1) },
        isBuiltIn: true
    )

    static let builtInPresets: [EQPresetData] = [
        .flat, .bassBoost, .vocalClarity, .loudness, .trebleBoost,
        .podcast, .techno, .deepHouse, .hardTechno, .minimal,
        .americanRap, .germanRap
    ]

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

    var bandwidthLabel: String {
        if bandwidth == Float(Int(bandwidth)) {
            return "Q \(Int(bandwidth))"
        }
        return String(format: "Q %.1f", bandwidth)
    }

    var gainLabel: String {
        if gain == 0 { return "0 dB" }
        if gain == Float(Int(gain)) {
            return String(format: "%+d dB", Int(gain))
        }
        return String(format: "%+.1f dB", gain)
    }
}
