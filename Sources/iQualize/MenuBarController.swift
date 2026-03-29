import AppKit

@available(macOS 14.2, *)
@MainActor
final class MenuBarController: NSObject, @preconcurrency NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let audioEngine: AudioEngine
    private let presetStore: PresetStore
    private var state: iQualizeState
    private var eqWindowController: EQWindowController?

    init(audioEngine: AudioEngine, presetStore: PresetStore) {
        self.audioEngine = audioEngine
        self.presetStore = presetStore
        self.state = iQualizeState.load()
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        // Rebuild menu on device changes
        audioEngine.onStateChange = { [weak self] in
            self?.updateIcon()
        }

        // Restore saved state and always start EQ
        if let preset = presetStore.preset(for: state.selectedPresetID) {
            audioEngine.activePreset = preset
        }
        audioEngine.preventClipping = state.preventClipping
        audioEngine.lowLatency = state.lowLatency
        audioEngine.setEnabled(true)
        updateIcon()
    }

    // MARK: - NSMenuDelegate — build menu fresh each time it opens

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Built-in presets (radio group)
        for preset in EQPresetData.builtInPresets {
            let item = NSMenuItem(title: preset.name,
                                  action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id.uuidString
            item.state = audioEngine.activePreset.id == preset.id ? .on : .off
            menu.addItem(item)
        }

        // Custom presets (if any)
        if !presetStore.customPresets.isEmpty {
            menu.addItem(.separator())
            for preset in presetStore.customPresets {
                let item = NSMenuItem(title: preset.name,
                                      action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id.uuidString
                item.state = audioEngine.activePreset.id == preset.id ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Prevent Clipping toggle
        let clippingItem = NSMenuItem(title: "Prevent Clipping",
                                       action: #selector(toggleClipping(_:)), keyEquivalent: "")
        clippingItem.target = self
        clippingItem.state = audioEngine.preventClipping ? .on : .off
        menu.addItem(clippingItem)

        // Low Latency toggle
        let latencyItem = NSMenuItem(title: "Low Latency",
                                      action: #selector(toggleLowLatency(_:)), keyEquivalent: "")
        latencyItem.target = self
        latencyItem.state = audioEngine.lowLatency ? .on : .off
        menu.addItem(latencyItem)

        menu.addItem(.separator())

        // Open standalone window
        let openItem = NSMenuItem(title: "Open iQualize",
                                   action: #selector(openEQSettings(_:)), keyEquivalent: ",")
        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Output device (non-interactive)
        let outputItem = NSMenuItem(title: "Output: \(audioEngine.outputDeviceName)",
                                     action: nil, keyEquivalent: "")
        outputItem.isEnabled = false
        menu.addItem(outputItem)

        // Error display
        if let error = audioEngine.error {
            let errorItem = NSMenuItem(title: "⚠ \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())

        // About
        let aboutItem = NSMenuItem(title: "About iQualize", action: #selector(showAbout(_:)),
                                    keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit iQualize", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleEQ(_ sender: NSMenuItem) {
        let newState = !audioEngine.isRunning
        audioEngine.setEnabled(newState)
        state.isEnabled = audioEngine.isRunning
        state.save()
        updateIcon()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let id = UUID(uuidString: uuidString),
              let preset = presetStore.preset(for: id) else { return }
        audioEngine.activePreset = preset
        state.selectedPresetID = preset.id
        state.save()
    }

    @objc private func openEQSettings(_ sender: NSMenuItem) {
        if eqWindowController == nil {
            eqWindowController = EQWindowController(audioEngine: audioEngine, presetStore: presetStore)
        }
        eqWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleClipping(_ sender: NSMenuItem) {
        audioEngine.preventClipping.toggle()
        state.preventClipping = audioEngine.preventClipping
        state.save()
    }

    @objc private func toggleLowLatency(_ sender: NSMenuItem) {
        audioEngine.lowLatency.toggle()
        state.lowLatency = audioEngine.lowLatency
        state.save()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "iQualize"
        alert.informativeText = "System-wide audio equalizer for macOS.\nVersion 0.2"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        audioEngine.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    private func updateIcon() {
        if let button = statusItem.button {
            button.title = ""
            let symbolName = "slider.vertical.3"
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "iQualize") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
                button.image?.isTemplate = true
            }
            button.appearsDisabled = !audioEngine.isRunning
        }
    }
}
