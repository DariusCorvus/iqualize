import Foundation

// MARK: - State Persistence

struct iQualizeState: Codable {
    var isEnabled: Bool
    var selectedPresetID: UUID
    var preventClipping: Bool
    var lowLatency: Bool

    static let defaultState = iQualizeState(
        isEnabled: false,
        selectedPresetID: EQPresetData.flat.id,
        preventClipping: true,
        lowLatency: false
    )

    private static let key = "com.iqualize.state"

    // Legacy migration keys
    private enum LegacyCodingKeys: String, CodingKey {
        case isEnabled
        case selectedPreset
        case preventClipping
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case selectedPresetID
        case preventClipping
        case lowLatency
    }

    init(isEnabled: Bool, selectedPresetID: UUID, preventClipping: Bool, lowLatency: Bool = false) {
        self.isEnabled = isEnabled
        self.selectedPresetID = selectedPresetID
        self.preventClipping = preventClipping
        self.lowLatency = lowLatency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? false
        preventClipping = (try? container.decode(Bool.self, forKey: .preventClipping)) ?? true
        lowLatency = (try? container.decode(Bool.self, forKey: .lowLatency)) ?? false

        if let id = try? container.decode(UUID.self, forKey: .selectedPresetID) {
            selectedPresetID = id
        } else {
            // Try legacy format: selectedPreset was a raw string like "flat", "bassBoost"
            let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)
            if let legacy = try? legacyContainer?.decode(String.self, forKey: .selectedPreset) {
                selectedPresetID = Self.migrateLegacyPreset(legacy)
            } else {
                selectedPresetID = EQPresetData.flat.id
            }
        }
    }

    private static func migrateLegacyPreset(_ rawValue: String) -> UUID {
        switch rawValue {
        case "flat": return EQPresetData.flat.id
        case "bassBoost": return EQPresetData.bassBoost.id
        case "vocalClarity": return EQPresetData.vocalClarity.id
        default: return EQPresetData.flat.id
        }
    }

    static func load() -> iQualizeState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(iQualizeState.self, from: data) else {
            return .defaultState
        }
        return state
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: iQualizeState.key)
        }
    }
}
