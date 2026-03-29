import Foundation
import Observation

@available(macOS 14.2, *)
@Observable
@MainActor
final class PresetStore {
    private(set) var customPresets: [EQPresetData] = []

    var allPresets: [EQPresetData] {
        EQPresetData.builtInPresets + customPresets
    }

    private static let key = "com.iqualize.customPresets"

    init() {
        load()
    }

    func preset(for id: UUID) -> EQPresetData? {
        allPresets.first { $0.id == id }
    }

    func saveCustomPreset(_ preset: EQPresetData) {
        if let index = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[index] = preset
        } else {
            customPresets.append(preset)
        }
        persist()
    }

    func deleteCustomPreset(id: UUID) {
        customPresets.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let presets = try? JSONDecoder().decode([EQPresetData].self, from: data) else {
            return
        }
        customPresets = presets
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
