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
        audioEngine.peakLimiter = state.peakLimiter
        audioEngine.lowLatency = state.lowLatency
        audioEngine.maxGainDB = state.maxGainDB
        audioEngine.bypassed = state.bypassed
        audioEngine.setEnabled(true)
        updateIcon()

        // Restore EQ window if it was open when the app last quit
        if state.windowOpen {
            openEQWindow()
        }
    }

    // MARK: - NSMenuDelegate — build menu fresh each time it opens

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Built-in presets
        let builtInHeader = NSMenuItem(title: "Built-in", action: nil, keyEquivalent: "")
        builtInHeader.isEnabled = false
        menu.addItem(builtInHeader)
        for preset in EQPresetData.builtInPresets {
            let item = NSMenuItem(title: preset.name,
                                  action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id.uuidString
            item.state = audioEngine.activePreset.id == preset.id ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        // Custom presets (if any)
        if !presetStore.customPresets.isEmpty {
            menu.addItem(.separator())
            let customHeader = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            customHeader.isEnabled = false
            menu.addItem(customHeader)
            for preset in presetStore.customPresets {
                let item = NSMenuItem(title: preset.name,
                                      action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id.uuidString
                item.state = audioEngine.activePreset.id == preset.id ? .on : .off
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Bypass EQ toggle
        let bypassItem = NSMenuItem(title: "Bypass EQ",
                                      action: #selector(toggleBypass(_:)), keyEquivalent: "b")
        bypassItem.keyEquivalentModifierMask = [.command]
        bypassItem.target = self
        bypassItem.state = audioEngine.bypassed ? .on : .off
        menu.addItem(bypassItem)

        // Peak Limiter toggle
        let clippingItem = NSMenuItem(title: "Peak Limiter",
                                       action: #selector(toggleClipping(_:)), keyEquivalent: "")
        clippingItem.target = self
        clippingItem.state = audioEngine.peakLimiter ? .on : .off
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

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let id = UUID(uuidString: uuidString),
              let preset = presetStore.preset(for: id) else { return }
        audioEngine.activePreset = preset
        state.selectedPresetID = preset.id
        state.save()
    }

    @objc private func openEQSettings(_ sender: NSMenuItem) {
        openEQWindow()
    }

    func openEQWindow() {
        if eqWindowController == nil {
            eqWindowController = EQWindowController(audioEngine: audioEngine, presetStore: presetStore)
            // Track window close to persist state
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidClose(_:)),
                name: NSWindow.willCloseNotification, object: eqWindowController?.window
            )
        }
        eqWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.windowOpen = true
        state.save()
    }

    @objc private func windowDidClose(_ notification: Notification) {
        state.windowOpen = false
        state.save()
    }

    @objc private func toggleBypass(_ sender: NSMenuItem) {
        audioEngine.bypassed.toggle()
        state.bypassed = audioEngine.bypassed
        state.save()
        updateIcon()
    }

    @objc private func toggleClipping(_ sender: NSMenuItem) {
        audioEngine.peakLimiter.toggle()
        state.peakLimiter = audioEngine.peakLimiter
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        alert.informativeText = "System-wide audio equalizer for macOS.\nVersion \(version)"
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
            let symbolName = audioEngine.bypassed ? "slider.vertical.3" : "slider.vertical.3"
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "iQualize") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
                button.image?.isTemplate = true
            }
            button.appearsDisabled = !audioEngine.isRunning || audioEngine.bypassed
        }
    }
}
