import Foundation

struct OutputDeviceProfile: Codable, Equatable, Sendable {
    var deviceUID: String
    var deviceName: String
    var isEnabled: Bool
    var presetID: UUID?
    var presetName: String
    var bypassed: Bool
    var inputGainDB: Float

    enum CodingKeys: String, CodingKey {
        case deviceUID, deviceName, isEnabled, presetID, presetName, bypassed, inputGainDB
    }

    init(deviceUID: String,
         deviceName: String,
         isEnabled: Bool,
         presetID: UUID?,
         presetName: String,
         bypassed: Bool,
         inputGainDB: Float) {
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.isEnabled = isEnabled
        self.presetID = presetID
        self.presetName = presetName
        self.bypassed = bypassed
        self.inputGainDB = inputGainDB
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceUID = try container.decode(String.self, forKey: .deviceUID)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? true
        presetID = try? container.decode(UUID.self, forKey: .presetID)
        presetName = try container.decode(String.self, forKey: .presetName)
        bypassed = (try? container.decode(Bool.self, forKey: .bypassed)) ?? false
        inputGainDB = (try? container.decode(Float.self, forKey: .inputGainDB)) ?? 0
    }
}

enum OutputDeviceProfileStore {
    private static let key = "com.iqualize.outputDeviceProfiles"

    static var hasProfiles: Bool {
        !loadAll().isEmpty
    }

    static func profile(for deviceUID: String) -> OutputDeviceProfile? {
        guard !deviceUID.isEmpty else { return nil }
        return loadAll()[deviceUID]
    }

    static func save(_ profile: OutputDeviceProfile) {
        guard !profile.deviceUID.isEmpty else { return }
        var profiles = loadAll()
        profiles[profile.deviceUID] = profile
        persist(profiles)
    }

    static func delete(deviceUID: String) {
        guard !deviceUID.isEmpty else { return }
        var profiles = loadAll()
        profiles.removeValue(forKey: deviceUID)
        persist(profiles)
    }

    private static func loadAll() -> [String: OutputDeviceProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([String: OutputDeviceProfile].self, from: data) else {
            return [:]
        }
        return profiles
    }

    private static func persist(_ profiles: [String: OutputDeviceProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
