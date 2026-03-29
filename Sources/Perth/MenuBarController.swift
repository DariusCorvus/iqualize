import AppKit

@available(macOS 14.2, *)
@MainActor
final class MenuBarController: NSObject, @preconcurrency NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let audioEngine: AudioEngine
    private var state: PerthState

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        self.state = PerthState.load()
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

        // Restore saved state
        audioEngine.selectedPreset = state.selectedPreset
        if state.isEnabled {
            audioEngine.setEnabled(true)
            updateIcon()
        }
    }

    // MARK: - NSMenuDelegate — build menu fresh each time it opens

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // EQ Toggle
        let toggleItem = NSMenuItem(title: audioEngine.isRunning ? "EQ On" : "EQ Off",
                                     action: #selector(toggleEQ(_:)), keyEquivalent: "e")
        toggleItem.keyEquivalentModifierMask = [.command]
        toggleItem.target = self
        toggleItem.state = audioEngine.isRunning ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Presets (radio group)
        for preset in EQPreset.allCases {
            let item = NSMenuItem(title: preset.displayName,
                                  action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = audioEngine.selectedPreset == preset ? .on : .off
            menu.addItem(item)
        }

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
        let aboutItem = NSMenuItem(title: "About Perth", action: #selector(showAbout(_:)),
                                    keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
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
        guard let rawValue = sender.representedObject as? String,
              let preset = EQPreset(rawValue: rawValue) else { return }
        audioEngine.selectedPreset = preset
        state.selectedPreset = preset
        state.save()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Perth"
        alert.informativeText = "System-wide audio equalizer for macOS.\nVersion 0.1"
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
            let symbolName = audioEngine.isRunning ? "slider.vertical.3" : "slider.vertical.3"
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Perth EQ") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
                button.image?.isTemplate = true
            }
            // Indicate active state with a badge-style approach
            button.appearsDisabled = !audioEngine.isRunning
        }
    }
}
