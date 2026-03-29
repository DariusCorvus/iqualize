import AppKit

@available(macOS 14.2, *)
@MainActor
final class EQWindowController: NSWindowController {
    private let audioEngine: AudioEngine
    private let presetStore: PresetStore

    private var eqToggle: NSButton!
    private var presetPicker: NSPopUpButton!
    private var addBandButton: NSButton!
    private var removeBandButton: NSButton!
    private var bandCountLabel: NSTextField!
    private var slidersContainer: NSStackView!
    private var sliders: [NSSlider] = []
    private var gainLabels: [NSTextField] = []
    private var freqLabels: [NSTextField] = []
    private var clippingCheckbox: NSButton!
    private var lowLatencyCheckbox: NSButton!
    private var outputLabel: NSTextField!
    private var deleteButton: NSButton!
    private var saveButton: NSButton!
    private var resetButton: NSButton!

    /// Snapshot of the preset when it was loaded/saved, for reset.
    private var savedPresetSnapshot: EQPresetData?

    /// Tracks whether the user has modified the active preset without saving.
    private var isModified = false

    init(audioEngine: AudioEngine, presetStore: PresetStore) {
        self.audioEngine = audioEngine
        self.presetStore = presetStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "iQualize"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupUI()
        syncUIToPreset()

        let previousCallback = audioEngine.onStateChange
        audioEngine.onStateChange = { [weak self] in
            previousCallback?()
            self?.updateOutputLabel()
            self?.updateEQToggle()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Row 1: Preset picker + Save + Reset + Delete
        let presetRow = NSStackView()
        presetRow.orientation = .horizontal
        presetRow.spacing = 8

        let presetLabel = NSTextField(labelWithString: "Preset:")
        presetPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPicker.target = self
        presetPicker.action = #selector(presetChanged(_:))

        saveButton = NSButton(title: "Save...", target: self, action: #selector(savePreset(_:)))
        saveButton.bezelStyle = .rounded

        resetButton = NSButton(title: "Reset", target: self, action: #selector(resetPreset(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.isEnabled = false

        deleteButton = NSButton(title: "Delete", target: self, action: #selector(deletePreset(_:)))
        deleteButton.bezelStyle = .rounded

        presetRow.addArrangedSubview(presetLabel)
        presetRow.addArrangedSubview(presetPicker)
        presetRow.addArrangedSubview(saveButton)
        presetRow.addArrangedSubview(resetButton)
        presetRow.addArrangedSubview(deleteButton)
        mainStack.addArrangedSubview(presetRow)

        // Row 2: Band count — add/remove
        let bandRow = NSStackView()
        bandRow.orientation = .horizontal
        bandRow.spacing = 8

        let bandLabel = NSTextField(labelWithString: "Bands:")

        bandCountLabel = NSTextField(labelWithString: "")
        bandCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        bandCountLabel.setContentHuggingPriority(.required, for: .horizontal)

        removeBandButton = NSButton(title: "−", target: self, action: #selector(removeBand(_:)))
        removeBandButton.bezelStyle = .rounded
        removeBandButton.setContentHuggingPriority(.required, for: .horizontal)

        addBandButton = NSButton(title: "+", target: self, action: #selector(addBand(_:)))
        addBandButton.bezelStyle = .rounded
        addBandButton.setContentHuggingPriority(.required, for: .horizontal)

        bandRow.addArrangedSubview(bandLabel)
        bandRow.addArrangedSubview(removeBandButton)
        bandRow.addArrangedSubview(bandCountLabel)
        bandRow.addArrangedSubview(addBandButton)
        mainStack.addArrangedSubview(bandRow)

        // Row 3: Sliders area
        slidersContainer = NSStackView()
        slidersContainer.orientation = .horizontal
        slidersContainer.alignment = .bottom
        slidersContainer.distribution = .fillEqually
        slidersContainer.spacing = 2
        slidersContainer.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(slidersContainer)
        NSLayoutConstraint.activate([
            slidersContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32),
        ])

        // Row 4: Bottom bar — EQ Enabled (left) + Prevent Clipping (right)
        eqToggle = NSButton(checkboxWithTitle: "EQ Enabled", target: self, action: #selector(toggleEQ(_:)))
        eqToggle.state = audioEngine.isRunning ? .on : .off

        clippingCheckbox = NSButton(checkboxWithTitle: "Prevent Clipping",
                                     target: self, action: #selector(toggleClipping(_:)))
        clippingCheckbox.state = audioEngine.preventClipping ? .on : .off

        lowLatencyCheckbox = NSButton(checkboxWithTitle: "Low Latency",
                                       target: self, action: #selector(toggleLowLatency(_:)))
        lowLatencyCheckbox.state = audioEngine.lowLatency ? .on : .off

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.distribution = .fill
        bottomRow.spacing = 8
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        bottomRow.addArrangedSubview(eqToggle)
        bottomRow.addArrangedSubview(spacer)
        bottomRow.addArrangedSubview(lowLatencyCheckbox)
        bottomRow.addArrangedSubview(clippingCheckbox)

        mainStack.addArrangedSubview(bottomRow)
        NSLayoutConstraint.activate([
            bottomRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32),
        ])

        // Row 5: Output device label
        outputLabel = NSTextField(labelWithString: "Output: \(audioEngine.outputDeviceName)")
        outputLabel.textColor = .secondaryLabelColor
        outputLabel.font = .systemFont(ofSize: 11)
        mainStack.addArrangedSubview(outputLabel)
    }

    // MARK: - Slider Building

    private func buildSliders() {
        for view in slidersContainer.arrangedSubviews {
            slidersContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        sliders.removeAll()
        gainLabels.removeAll()
        freqLabels.removeAll()

        let bands = audioEngine.activePreset.bands

        for (i, band) in bands.enumerated() {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 4

            let gainLabel = NSTextField(labelWithString: band.gainLabel)
            gainLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            gainLabel.alignment = .center
            gainLabel.setContentHuggingPriority(.required, for: .vertical)
            gainLabels.append(gainLabel)

            let slider = NSSlider(value: Double(band.gain), minValue: -12, maxValue: 12,
                                  target: self, action: #selector(sliderMoved(_:)))
            slider.isVertical = true
            slider.numberOfTickMarks = 25
            slider.allowsTickMarkValuesOnly = false
            slider.tag = i
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.heightAnchor.constraint(equalToConstant: 180).isActive = true
            sliders.append(slider)

            let freqLabel = NSTextField(labelWithString: band.frequencyLabel)
            freqLabel.font = .systemFont(ofSize: 9)
            freqLabel.alignment = .center
            freqLabel.textColor = .secondaryLabelColor
            freqLabel.setContentHuggingPriority(.required, for: .vertical)
            freqLabels.append(freqLabel)

            column.addArrangedSubview(gainLabel)
            column.addArrangedSubview(slider)
            column.addArrangedSubview(freqLabel)

            slidersContainer.addArrangedSubview(column)
        }

        let neededWidth = CGFloat(bands.count * 40 + 32)
        if let window = self.window {
            var frame = window.frame
            let newWidth = max(neededWidth, 400)
            frame.size.width = newWidth
            window.setFrame(frame, display: true, animate: true)
        }

        updateBandButtons()
    }

    // MARK: - Sync UI ↔ Engine

    private func syncUIToPreset() {
        populatePresetPicker()
        buildSliders()
        updateDeleteButton()
        updateOutputLabel()
        updateEQToggle()
        clippingCheckbox.state = audioEngine.preventClipping ? .on : .off
        lowLatencyCheckbox.state = audioEngine.lowLatency ? .on : .off
        savedPresetSnapshot = audioEngine.activePreset
        isModified = false
        resetButton.isEnabled = false
        updateWindowTitle()
    }

    private func populatePresetPicker() {
        presetPicker.removeAllItems()
        for preset in presetStore.allPresets {
            presetPicker.addItem(withTitle: preset.name)
            presetPicker.lastItem?.representedObject = preset.id.uuidString
        }

        let active = audioEngine.activePreset
        let inStore = presetStore.allPresets.contains { $0.id == active.id }
        if !inStore {
            // Unsaved fork — add with * to indicate it's not saved
            presetPicker.addItem(withTitle: "\(active.name)*")
            presetPicker.lastItem?.representedObject = active.id.uuidString
        } else if isModified {
            // Saved preset with unsaved changes — update its title with *
            for item in presetPicker.itemArray {
                if (item.representedObject as? String) == active.id.uuidString {
                    item.title = "\(active.name)*"
                    break
                }
            }
        }

        let currentID = active.id.uuidString
        for (i, item) in presetPicker.itemArray.enumerated() {
            if (item.representedObject as? String) == currentID {
                presetPicker.selectItem(at: i)
                break
            }
        }
    }

    private func updateDeleteButton() {
        deleteButton.isEnabled = !audioEngine.activePreset.isBuiltIn
    }

    private func updateOutputLabel() {
        outputLabel.stringValue = "Output: \(audioEngine.outputDeviceName)"
    }

    private func updateEQToggle() {
        eqToggle.state = audioEngine.isRunning ? .on : .off
    }

    private func updateBandButtons() {
        let count = audioEngine.activePreset.bands.count
        removeBandButton.isEnabled = count > EQPresetData.minBandCount
        addBandButton.isEnabled = count < EQPresetData.maxBandCount
        bandCountLabel.stringValue = "\(count)"
    }

    /// If the active preset is built-in, fork it into a custom copy before editing.
    /// Returns the mutable preset to modify.
    private func forkIfBuiltIn() {
        guard audioEngine.activePreset.isBuiltIn else { return }
        let custom = EQPresetData(
            id: UUID(),
            name: "\(audioEngine.activePreset.name) (Custom)",
            bands: audioEngine.activePreset.bands,
            isBuiltIn: false
        )
        audioEngine.activePreset = custom
        savedPresetSnapshot = custom
        populatePresetPicker()
        updateDeleteButton()
    }

    private func markModified() {
        isModified = true
        resetButton.isEnabled = true
        populatePresetPicker()
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        let name = audioEngine.activePreset.name
        window?.title = isModified ? "iQualize — \(name)*" : "iQualize — \(name)"
    }

    // MARK: - Actions

    @objc private func toggleEQ(_ sender: NSButton) {
        let enable = sender.state == .on
        audioEngine.setEnabled(enable)
        var state = iQualizeState.load()
        state.isEnabled = audioEngine.isRunning
        state.save()
        updateEQToggle()
    }

    @objc private func toggleClipping(_ sender: NSButton) {
        audioEngine.preventClipping = sender.state == .on
        var state = iQualizeState.load()
        state.preventClipping = audioEngine.preventClipping
        state.save()
    }

    @objc private func toggleLowLatency(_ sender: NSButton) {
        audioEngine.lowLatency = sender.state == .on
        var state = iQualizeState.load()
        state.lowLatency = audioEngine.lowLatency
        state.save()
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        guard let uuidString = sender.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: uuidString),
              let preset = presetStore.preset(for: id) else { return }
        audioEngine.activePreset = preset
        savedPresetSnapshot = preset
        buildSliders()
        updateDeleteButton()
        isModified = false
        resetButton.isEnabled = false
        updateWindowTitle()
        saveState()
    }

    @objc private func addBand(_ sender: NSButton) {
        guard audioEngine.activePreset.bands.count < EQPresetData.maxBandCount else { return }
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let newFreq = preset.suggestNewBandFrequency()
        let newBand = EQBand(frequency: newFreq, gain: 0)
        preset.bands.append(newBand)
        preset.bands.sort { $0.frequency < $1.frequency }
        audioEngine.activePreset = preset

        buildSliders()
        markModified()
    }

    @objc private func removeBand(_ sender: NSButton) {
        guard audioEngine.activePreset.bands.count > EQPresetData.minBandCount else { return }
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        // Remove the last band
        preset.bands.removeLast()
        audioEngine.activePreset = preset

        buildSliders()
        markModified()
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let index = sender.tag
        guard index < audioEngine.activePreset.bands.count else { return }
        forkIfBuiltIn()
        let gain = Float(sender.doubleValue)

        var preset = audioEngine.activePreset
        preset.bands[index].gain = gain
        audioEngine.activePreset = preset

        gainLabels[index].stringValue = preset.bands[index].gainLabel
        markModified()
    }

    @objc private func resetPreset(_ sender: NSButton) {
        guard let snapshot = savedPresetSnapshot else { return }
        audioEngine.activePreset = snapshot

        buildSliders()
        isModified = false
        resetButton.isEnabled = false
        updateWindowTitle()
    }

    @objc private func savePreset(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Save Preset"
        alert.informativeText = "Enter a name for this preset:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        nameField.stringValue = audioEngine.activePreset.isBuiltIn
            ? "" : audioEngine.activePreset.name
        nameField.placeholderString = "My Custom EQ"
        alert.accessoryView = nameField

        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if audioEngine.activePreset.isBuiltIn {
            let newPreset = EQPresetData(
                id: UUID(),
                name: name,
                bands: audioEngine.activePreset.bands,
                isBuiltIn: false
            )
            presetStore.saveCustomPreset(newPreset)
            audioEngine.activePreset = newPreset
        } else {
            var updated = audioEngine.activePreset
            updated.name = name
            presetStore.saveCustomPreset(updated)
            audioEngine.activePreset = updated
        }

        syncUIToPreset()
        saveState()
    }

    @objc private func deletePreset(_ sender: NSButton) {
        guard !audioEngine.activePreset.isBuiltIn else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \"\(audioEngine.activePreset.name)\"?"
        alert.informativeText = "This preset will be permanently removed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        presetStore.deleteCustomPreset(id: audioEngine.activePreset.id)
        audioEngine.activePreset = .flat
        syncUIToPreset()
        saveState()
    }

    private func saveState() {
        var state = iQualizeState.load()
        state.selectedPresetID = audioEngine.activePreset.id
        state.save()
    }
}
