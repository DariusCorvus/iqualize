import AppKit
import ServiceManagement

@available(macOS 14.2, *)
@MainActor
final class MenuBarController: NSObject, @preconcurrency NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let audioEngine: AudioEngine
    private let presetStore: PresetStore
    private var eqWindowController: EQWindowController?

    init(audioEngine: AudioEngine, presetStore: PresetStore) {
        self.audioEngine = audioEngine
        self.presetStore = presetStore
        super.init()
        let state = iQualizeState.load()

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
        audioEngine.maxGainDB = state.maxGainDB
        audioEngine.bypassed = state.bypassed
        audioEngine.balance = state.balance
        audioEngine.setEnabled(true)
        updateIcon()

        // Restore EQ window if it was open when the app last quit
        if state.windowOpen {
            openEQWindow()
        }
    }

    // MARK: - NSMenuDelegate — build menu fresh each time it opens

    func menuNeedsUpdate(_ menu: NSMenu) {
        if NSEvent.modifierFlags.contains(.option) {
            menu.removeAllItems()
            menu.cancelTracking()
            openEQWindow()
            return
        }
        populateMenu(menu)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Open standalone window
        let openItem = NSMenuItem(title: "Open iQualize",
                                   action: #selector(openEQSettings(_:)), keyEquivalent: ",")
        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Presets submenu
        let presetMenuItem = NSMenuItem(title: "Presets (\(audioEngine.activePreset.name))",
                                         action: nil, keyEquivalent: "")
        let presetSubmenu = NSMenu()

        let builtInHeader = NSMenuItem(title: "Built-in", action: nil, keyEquivalent: "")
        builtInHeader.isEnabled = false
        presetSubmenu.addItem(builtInHeader)
        for preset in EQPresetData.builtInPresets {
            let item = NSMenuItem(title: preset.name,
                                  action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id.uuidString
            item.state = audioEngine.activePreset.id == preset.id ? .on : .off
            item.indentationLevel = 1
            presetSubmenu.addItem(item)
        }

        if !presetStore.customPresets.isEmpty {
            presetSubmenu.addItem(.separator())
            let customHeader = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            customHeader.isEnabled = false
            presetSubmenu.addItem(customHeader)
            for preset in presetStore.customPresets {
                let item = NSMenuItem(title: preset.name,
                                      action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id.uuidString
                item.state = audioEngine.activePreset.id == preset.id ? .on : .off
                item.indentationLevel = 1
                presetSubmenu.addItem(item)
            }
        }

        presetMenuItem.submenu = presetSubmenu
        menu.addItem(presetMenuItem)

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

        // Hide from Dock toggle
        let dockItem = NSMenuItem(title: "Hide from Dock",
                                   action: #selector(toggleHideFromDock(_:)), keyEquivalent: "")
        dockItem.target = self
        dockItem.state = iQualizeState.load().hideFromDock ? .on : .off
        menu.addItem(dockItem)

        // Start at Login toggle
        let loginItem = NSMenuItem(title: "Start at Login",
                                    action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

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
        var s = iQualizeState.load()
        s.selectedPresetID = preset.id
        s.save()
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
        var s = iQualizeState.load()
        s.windowOpen = true
        s.save()
    }

    @objc private func windowDidClose(_ notification: Notification) {
        var s = iQualizeState.load()
        s.windowOpen = false
        s.save()
    }

    @objc private func toggleBypass(_ sender: NSMenuItem) {
        audioEngine.bypassed.toggle()
        var s = iQualizeState.load()
        s.bypassed = audioEngine.bypassed
        s.save()
        updateIcon()
    }

    @objc private func toggleClipping(_ sender: NSMenuItem) {
        audioEngine.peakLimiter.toggle()
        var s = iQualizeState.load()
        s.peakLimiter = audioEngine.peakLimiter
        s.save()
    }

    @objc private func toggleStartAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to update login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        var s = iQualizeState.load()
        s.startAtLogin = SMAppService.mainApp.status == .enabled
        s.save()
    }

    @objc private func toggleHideFromDock(_ sender: NSMenuItem) {
        var s = iQualizeState.load()
        s.hideFromDock.toggle()
        s.save()
        NSApp.setActivationPolicy(s.hideFromDock ? .accessory : .regular)
        if !s.hideFromDock {
            NSApp.activate(ignoringOtherApps: true)
        }
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
