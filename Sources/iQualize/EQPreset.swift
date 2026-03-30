import Foundation

// MARK: - State Persistence

struct iQualizeState: Codable {
    var isEnabled: Bool
    var selectedPresetID: UUID
    var peakLimiter: Bool
    var windowOpen: Bool
    var maxGainDB: Float
    var bypassed: Bool
    var autoScale: Bool
    var preEqSpectrumEnabled: Bool
    var postEqSpectrumEnabled: Bool
    var hideFromDock: Bool

    static let defaultState = iQualizeState(
        isEnabled: false,
        selectedPresetID: EQPresetData.flat.id,
        peakLimiter: true,
        windowOpen: false,
        maxGainDB: 12,
        bypassed: false,
        autoScale: true,
        preEqSpectrumEnabled: false,
        postEqSpectrumEnabled: false,
        hideFromDock: false
    )

    private static let key = "com.iqualize.state"

    init(isEnabled: Bool, selectedPresetID: UUID, peakLimiter: Bool, windowOpen: Bool = false, maxGainDB: Float = 12, bypassed: Bool = false, autoScale: Bool = true, preEqSpectrumEnabled: Bool = false, postEqSpectrumEnabled: Bool = false, hideFromDock: Bool = false) {
        self.isEnabled = isEnabled
        self.selectedPresetID = selectedPresetID
        self.peakLimiter = peakLimiter
        self.windowOpen = windowOpen
        self.maxGainDB = maxGainDB
        self.bypassed = bypassed
        self.autoScale = autoScale
        self.preEqSpectrumEnabled = preEqSpectrumEnabled
        self.postEqSpectrumEnabled = postEqSpectrumEnabled
        self.hideFromDock = hideFromDock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? false
        selectedPresetID = (try? container.decode(UUID.self, forKey: .selectedPresetID)) ?? EQPresetData.flat.id
        peakLimiter = (try? container.decode(Bool.self, forKey: .peakLimiter)) ?? true
        windowOpen = (try? container.decode(Bool.self, forKey: .windowOpen)) ?? false
        maxGainDB = (try? container.decode(Float.self, forKey: .maxGainDB)) ?? 12
        bypassed = (try? container.decode(Bool.self, forKey: .bypassed)) ?? false
        autoScale = (try? container.decode(Bool.self, forKey: .autoScale)) ?? true
        preEqSpectrumEnabled = (try? container.decode(Bool.self, forKey: .preEqSpectrumEnabled)) ?? false
        postEqSpectrumEnabled = (try? container.decode(Bool.self, forKey: .postEqSpectrumEnabled)) ?? false
        hideFromDock = (try? container.decode(Bool.self, forKey: .hideFromDock)) ?? false
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
