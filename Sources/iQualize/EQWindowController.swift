import AppKit

@available(macOS 14.2, *)
@MainActor
final class UnitTextField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in
                self?.onFocus?()
                self?.currentEditor()?.selectAll(nil)
            }
        }
        return result
    }
}

@available(macOS 14.2, *)
@MainActor
final class ClickThroughView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        super.mouseDown(with: event)
    }
}

@available(macOS 14.2, *)
@MainActor
final class EQWindowController: NSWindowController, NSTextFieldDelegate {
    private let audioEngine: AudioEngine
    private let presetStore: PresetStore

    private var eqToggle: NSButton!
    private var presetPicker: NSPopUpButton!
    private var slidersContainer: NSStackView!
    private var sliders: [NSSlider] = []
    private var gainLabels: [UnitTextField] = []
    private var freqLabels: [UnitTextField] = []
    private var qLabels: [UnitTextField] = []
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

        // Don't auto-focus any input on open
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }

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
        let clickView = ClickThroughView()
        window?.contentView = clickView
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

        // Divider above bands
        let topDivider = NSBox()
        topDivider.boxType = .separator
        mainStack.addArrangedSubview(topDivider)
        topDivider.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32).isActive = true

        // Row 2: Sliders area
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

        // Divider below bands
        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator
        mainStack.addArrangedSubview(bottomDivider)
        bottomDivider.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32).isActive = true

        // Row 3: Bottom bar — EQ Enabled (left) + Prevent Clipping (right)
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
        qLabels.removeAll()

        let bands = audioEngine.activePreset.bands
        let canAdd = bands.count < EQPresetData.maxBandCount
        var firstSlider: NSSlider?

        // Left "+" placeholder
        var leftAddButton: NSView?
        if canAdd {
            let add = makeAddButton(side: .left)
            leftAddButton = add
            slidersContainer.addArrangedSubview(add)
        }

        for (i, band) in bands.enumerated() {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 4

            let gainLabel = UnitTextField(string: band.gainLabel)
            gainLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            gainLabel.alignment = .center
            gainLabel.bezelStyle = .roundedBezel
            gainLabel.isEditable = true
            gainLabel.delegate = self
            gainLabel.tag = i
            gainLabel.setContentHuggingPriority(.required, for: .vertical)
            gainLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
            gainLabel.onFocus = { [weak self] in
                guard let self, i < self.audioEngine.activePreset.bands.count else { return }
                gainLabel.stringValue = Self.formatRawFloat(self.audioEngine.activePreset.bands[i].gain)
            }
            gainLabels.append(gainLabel)

            let slider = NSSlider(value: Double(band.gain), minValue: -12, maxValue: 12,
                                  target: self, action: #selector(sliderMoved(_:)))
            slider.isVertical = true
            slider.numberOfTickMarks = 25
            slider.allowsTickMarkValuesOnly = false
            slider.tag = i
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.heightAnchor.constraint(equalToConstant: 180).isActive = true
            if firstSlider == nil { firstSlider = slider }
            sliders.append(slider)

            let freqLabel = UnitTextField(string: band.frequencyLabel)
            freqLabel.font = .systemFont(ofSize: 9)
            freqLabel.alignment = .center
            freqLabel.bezelStyle = .roundedBezel
            freqLabel.isEditable = true
            freqLabel.delegate = self
            freqLabel.tag = i
            freqLabel.setContentHuggingPriority(.required, for: .vertical)
            freqLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
            freqLabel.onFocus = { [weak self] in
                guard let self, i < self.audioEngine.activePreset.bands.count else { return }
                freqLabel.stringValue = Self.formatRawFloat(self.audioEngine.activePreset.bands[i].frequency)
            }
            freqLabels.append(freqLabel)

            let qLabel = UnitTextField(string: band.bandwidthLabel)
            qLabel.font = .systemFont(ofSize: 9)
            qLabel.alignment = .center
            qLabel.bezelStyle = .roundedBezel
            qLabel.isEditable = true
            qLabel.delegate = self
            qLabel.tag = i
            qLabel.setContentHuggingPriority(.required, for: .vertical)
            qLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
            qLabel.onFocus = { [weak self] in
                guard let self, i < self.audioEngine.activePreset.bands.count else { return }
                qLabel.stringValue = Self.formatRawFloat(self.audioEngine.activePreset.bands[i].bandwidth)
            }
            qLabels.append(qLabel)

            column.addArrangedSubview(gainLabel)
            column.addArrangedSubview(slider)
            column.addArrangedSubview(freqLabel)
            column.addArrangedSubview(qLabel)

            // Right-click to delete band
            let menu = NSMenu()
            let deleteItem = NSMenuItem(title: "Delete Band", action: #selector(deleteBandFromMenu(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.tag = i
            menu.addItem(deleteItem)
            column.menu = menu

            slidersContainer.addArrangedSubview(column)
        }

        // Right "+" placeholder
        var rightAddButton: NSView?
        if canAdd {
            let add = makeAddButton(side: .right)
            rightAddButton = add
            slidersContainer.addArrangedSubview(add)
        }

        // Align + buttons to the first slider's vertical center
        if let slider = firstSlider {
            if let btn = leftAddButton?.subviews.first {
                btn.centerYAnchor.constraint(equalTo: slider.centerYAnchor).isActive = true
            }
            if let btn = rightAddButton?.subviews.first {
                btn.centerYAnchor.constraint(equalTo: slider.centerYAnchor).isActive = true
            }
        }

        let neededWidth = CGFloat(bands.count * 40 + 32)
        if let window = self.window {
            var frame = window.frame
            let newWidth = max(neededWidth, 400)
            frame.size.width = newWidth
            window.setFrame(frame, display: true, animate: true)
        }

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

    private enum AddSide { case left, right }

    private func makeAddButton(side: AddSide) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "+", target: self,
                              action: side == .left ? #selector(addBandLeft(_:)) : #selector(addBandRight(_:)))
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 16, weight: .light)
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false

        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            wrapper.widthAnchor.constraint(equalToConstant: 24),
        ])

        return wrapper
    }

    @objc private func deleteBandFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < audioEngine.activePreset.bands.count,
              audioEngine.activePreset.bands.count > EQPresetData.minBandCount else { return }

        let band = audioEngine.activePreset.bands[index]
        let alert = NSAlert()
        alert.messageText = "Delete Band?"
        alert.informativeText = "Remove the \(band.frequencyLabel) band at \(band.gainLabel)?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        preset.bands.remove(at: index)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
    }

    @objc private func addBandLeft(_ sender: NSButton) {
        guard audioEngine.activePreset.bands.count < EQPresetData.maxBandCount else { return }
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let leftmost = preset.bands.first ?? EQBand(frequency: 100, gain: 0)
        preset.bands.insert(EQBand(frequency: leftmost.frequency, gain: leftmost.gain, bandwidth: leftmost.bandwidth), at: 0)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
    }

    @objc private func addBandRight(_ sender: NSButton) {
        guard audioEngine.activePreset.bands.count < EQPresetData.maxBandCount else { return }
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let rightmost = preset.bands.last ?? EQBand(frequency: 1000, gain: 0)
        preset.bands.append(EQBand(frequency: rightmost.frequency, gain: rightmost.gain, bandwidth: rightmost.bandwidth))
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
    }

    // MARK: - NSTextFieldDelegate (editable dB / Hz / Q inputs)

    private static func formatRawFloat(_ v: Float) -> String {
        v == Float(Int(v)) ? "\(Int(v))" : String(format: "%.1f", v)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? UnitTextField else { return }
        let index = field.tag
        guard index < audioEngine.activePreset.bands.count else { return }

        let band = audioEngine.activePreset.bands[index]

        if gainLabels.contains(field) {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if let value = Float(text) {
                let clamped = min(max(value, -12), 12)
                if clamped != band.gain {
                    forkIfBuiltIn()
                    var preset = audioEngine.activePreset
                    preset.bands[index].gain = clamped
                    audioEngine.activePreset = preset
                    sliders[index].doubleValue = Double(clamped)
                    markModified()
                }
            }
            field.stringValue = audioEngine.activePreset.bands[index].gainLabel
        } else if freqLabels.contains(field) {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if let value = Float(text) {
                let clamped = min(max(value, 20), 20000)
                if clamped != band.frequency {
                    forkIfBuiltIn()
                    var preset = audioEngine.activePreset
                    preset.bands[index].frequency = clamped
                    audioEngine.activePreset = preset
                    markModified()
                }
            }
            field.stringValue = audioEngine.activePreset.bands[index].frequencyLabel
        } else if qLabels.contains(field) {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if let value = Float(text), value > 0 {
                let clamped = min(max(value, 0.1), 10)
                if clamped != band.bandwidth {
                    forkIfBuiltIn()
                    var preset = audioEngine.activePreset
                    preset.bands[index].bandwidth = clamped
                    audioEngine.activePreset = preset
                    markModified()
                }
            }
            field.stringValue = audioEngine.activePreset.bands[index].bandwidthLabel
        }
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
        window?.makeFirstResponder(nil)
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
        window?.makeFirstResponder(nil)

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
