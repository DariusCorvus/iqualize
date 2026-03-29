import Foundation

enum EQPreset: String, CaseIterable, Codable {
    case flat
    case bassBoost
    case vocalClarity

    var displayName: String {
        switch self {
        case .flat: return "Flat"
        case .bassBoost: return "Bass Boost"
        case .vocalClarity: return "Vocal Clarity"
        }
    }

    /// Gain values in dB for each of the 10 bands.
    /// Order: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
    var bands: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:
            return [10, 10, 8, 4, 0, 0, 0, 0, 0, 0]
        case .vocalClarity:
            return [-6, -6, -4, 0, 0, 6, 6, 4, 0, 0]
        }
    }

    /// Automatic preamp reduction to prevent clipping.
    /// Uses half the max boost as a compromise between clipping prevention and volume.
    /// Full reduction (-maxBoost) is too quiet; no reduction clips on loud passages.
    /// Half reduction keeps most content clean while staying closer to original volume.
    var preampGain: Float {
        let maxBoost = bands.max() ?? 0
        return maxBoost > 0 ? -(maxBoost * 0.5) : 0
    }

    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = 10
}

// MARK: - State Persistence

struct PerthState: Codable {
    var isEnabled: Bool
    var selectedPreset: EQPreset
    var preventClipping: Bool

    static let defaultState = PerthState(isEnabled: false, selectedPreset: .flat, preventClipping: true)

    private static let key = "com.perth.state"

    static func load() -> PerthState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(PerthState.self, from: data) else {
            return .defaultState
        }
        return state
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: PerthState.key)
        }
    }
}
