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
    var startAtLogin: Bool
    var balance: Float
    var splitChannelEnabled: Bool
    var activeChannel: String?
    var inputGainDB: Float
    var outputGainDB: Float
    var showBandwidthAsQ: Bool
    /// User-picked Pre-EQ spectrum color as `#RRGGBB` (sRGB). nil = use the dynamic system color.
    var preEqSpectrumColorHex: String?
    /// User-picked Post-EQ spectrum color as `#RRGGBB` (sRGB). nil = use the dynamic system color.
    var postEqSpectrumColorHex: String?

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
        hideFromDock: false,
        startAtLogin: false,
        balance: 0.0,
        splitChannelEnabled: false,
        activeChannel: nil,
        inputGainDB: 0.0,
        outputGainDB: 0.0,
        showBandwidthAsQ: true
    )

    private static let key = "com.iqualize.state"

    init(isEnabled: Bool, selectedPresetID: UUID, peakLimiter: Bool, windowOpen: Bool = false, maxGainDB: Float = 12, bypassed: Bool = false, autoScale: Bool = true, preEqSpectrumEnabled: Bool = false, postEqSpectrumEnabled: Bool = false, hideFromDock: Bool = false, startAtLogin: Bool = false, balance: Float = 0.0, splitChannelEnabled: Bool = false, activeChannel: String? = nil, inputGainDB: Float = 0.0, outputGainDB: Float = 0.0, showBandwidthAsQ: Bool = true, preEqSpectrumColorHex: String? = nil, postEqSpectrumColorHex: String? = nil) {
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
        self.startAtLogin = startAtLogin
        self.balance = balance
        self.splitChannelEnabled = splitChannelEnabled
        self.activeChannel = activeChannel
        self.inputGainDB = inputGainDB
        self.outputGainDB = outputGainDB
        self.showBandwidthAsQ = showBandwidthAsQ
        self.preEqSpectrumColorHex = preEqSpectrumColorHex
        self.postEqSpectrumColorHex = postEqSpectrumColorHex
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
        startAtLogin = (try? container.decode(Bool.self, forKey: .startAtLogin)) ?? false
        balance = (try? container.decode(Float.self, forKey: .balance)) ?? 0.0
        splitChannelEnabled = (try? container.decode(Bool.self, forKey: .splitChannelEnabled)) ?? false
        activeChannel = try? container.decode(String.self, forKey: .activeChannel)
        inputGainDB = (try? container.decode(Float.self, forKey: .inputGainDB)) ?? 0.0
        outputGainDB = (try? container.decode(Float.self, forKey: .outputGainDB)) ?? 0.0
        showBandwidthAsQ = (try? container.decode(Bool.self, forKey: .showBandwidthAsQ)) ?? true
        preEqSpectrumColorHex = try? container.decode(String.self, forKey: .preEqSpectrumColorHex)
        postEqSpectrumColorHex = try? container.decode(String.self, forKey: .postEqSpectrumColorHex)
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
