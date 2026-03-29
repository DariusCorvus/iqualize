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

// MARK: - Drag handle view

@available(macOS 14.2, *)
@MainActor
final class DragHandleView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 14) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dotColor = NSColor.tertiaryLabelColor
        ctx.setFillColor(dotColor.cgColor)

        // Draw a 3x2 dot grid centered in the view
        let dotSize: CGFloat = 2.5
        let spacingX: CGFloat = 5
        let spacingY: CGFloat = 4
        let cols = 3
        let rows = 2
        let totalW = CGFloat(cols - 1) * spacingX + dotSize
        let totalH = CGFloat(rows - 1) * spacingY + dotSize
        let startX = (bounds.width - totalW) / 2
        let startY = (bounds.height - totalH) / 2

        for row in 0..<rows {
            for col in 0..<cols {
                let x = startX + CGFloat(col) * spacingX
                let y = startY + CGFloat(row) * spacingY
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: dotSize, height: dotSize))
            }
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - Drag-and-drop band column

private let bandDragType = NSPasteboard.PasteboardType("com.iqualize.band")

@available(macOS 14.2, *)
@MainActor
final class DraggableBandColumn: NSStackView, NSDraggingSource {
    var bandIndex: Int = 0
    let dragHandle = DragHandleView()
    private var isDraggingFromHandle = false

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func setupHandle() {
        dragHandle.wantsLayer = true
        dragHandle.layer?.cornerRadius = 3
        dragHandle.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        dragHandle.layer?.borderWidth = 0.5
        dragHandle.layer?.borderColor = NSColor.separatorColor.cgColor
        dragHandle.toolTip = "Drag to reorder"
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        // Match input width
        dragHandle.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let handleFrame = dragHandle.convert(dragHandle.bounds, to: self)
        isDraggingFromHandle = handleFrame.contains(loc)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingFromHandle else {
            super.mouseDragged(with: event)
            return
        }

        // Highlight the column being dragged
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor

        let item = NSDraggingItem(pasteboardWriter: "\(bandIndex)" as NSString)
        let snapshot = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: snapshot)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(snapshot)
        item.setDraggingFrame(bounds, contents: image)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        layer?.backgroundColor = nil
        isDraggingFromHandle = false
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingFromHandle = false
        layer?.backgroundColor = nil
        super.mouseUp(with: event)
    }
}

@available(macOS 14.2, *)
@MainActor
final class BandDropTarget: NSStackView {
    var onReorder: ((_ from: Int, _ to: Int) -> Void)?
    private var dropIndex: Int?
    private let indicator = NSView()

    func setupDropTarget() {
        registerForDraggedTypes([bandDragType, .string])
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        indicator.isHidden = true
        addSubview(indicator)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        indicator.isHidden = false
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let loc = convert(sender.draggingLocation, from: nil)
        // Find insertion index among band columns (skip + buttons)
        let columns = arrangedSubviews.filter { $0 is DraggableBandColumn }
        var insertionIndex = columns.count
        for (i, col) in columns.enumerated() {
            let mid = col.frame.midX
            if loc.x < mid {
                insertionIndex = i
                break
            }
        }
        dropIndex = insertionIndex

        // Position indicator
        let x: CGFloat
        if insertionIndex < columns.count {
            x = columns[insertionIndex].frame.minX - 1
        } else if let last = columns.last {
            x = last.frame.maxX + 1
        } else {
            x = 0
        }
        indicator.frame = NSRect(x: x, y: 0, width: 2, height: bounds.height)
        indicator.isHidden = false

        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        indicator.isHidden = true
        dropIndex = nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        indicator.isHidden = true
        guard let dropIdx = dropIndex,
              let str = sender.draggingPasteboard.string(forType: .string),
              let fromIndex = Int(str) else { return false }

        var toIndex = dropIdx
        // Adjust: if dropping after the source, account for removal
        if toIndex > fromIndex { toIndex -= 1 }
        if toIndex != fromIndex {
            onReorder?(fromIndex, toIndex)
        }
        dropIndex = nil
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        indicator.isHidden = true
        dropIndex = nil
    }
}

@available(macOS 14.2, *)
@MainActor
final class EQWindowController: NSWindowController, NSTextFieldDelegate {
    private let audioEngine: AudioEngine
    private let presetStore: PresetStore

    private var eqToggle: NSButton!
    private var presetPicker: NSPopUpButton!
    private var slidersContainer: BandDropTarget!
    private var sliders: [NSSlider] = []
    private var gainLabels: [UnitTextField] = []
    private var freqLabels: [UnitTextField] = []
    private var qLabels: [UnitTextField] = []
    private var clippingCheckbox: NSButton!
    private var lowLatencyCheckbox: NSButton!
    private var maxGainPicker: NSPopUpButton!
    private var outputLabel: NSTextField!
    private var newButton: NSButton!
    private var saveControl: NSSegmentedControl!
    private var saveDropdownMenu: NSMenu!
    private var resetButton: NSButton!
    private var deleteButton: NSButton!
    private var importExportButton: NSPopUpButton!

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

        // Row 1: Preset picker + action buttons
        let presetRow = NSStackView()
        presetRow.orientation = .horizontal
        presetRow.spacing = 6

        presetPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPicker.target = self
        presetPicker.action = #selector(presetChanged(_:))

        newButton = NSButton(title: "New", target: self, action: #selector(newPreset(_:)))
        newButton.bezelStyle = .rounded

        saveControl = NSSegmentedControl(labels: ["Save", ""], trackingMode: .momentary,
                                          target: self, action: #selector(saveSegmentClicked(_:)))
        saveControl.setWidth(50, forSegment: 0)
        saveControl.setWidth(24, forSegment: 1)
        saveControl.setShowsMenuIndicator(true, forSegment: 1)
        saveDropdownMenu = NSMenu()
        let saveAsItem = NSMenuItem(title: "Save As…", action: #selector(saveAsPreset(_:)), keyEquivalent: "")
        saveAsItem.target = self
        saveDropdownMenu.addItem(saveAsItem)

        resetButton = NSButton(title: "Reset", target: self, action: #selector(resetPreset(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.isEnabled = false

        deleteButton = NSButton(title: "Delete", target: self, action: #selector(deletePreset(_:)))
        deleteButton.bezelStyle = .rounded

        // Import/Export gear menu
        importExportButton = NSPopUpButton(frame: .zero, pullsDown: true)
        importExportButton.addItem(withTitle: "")
        if let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "More") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            importExportButton.item(at: 0)?.image = gearImage.withSymbolConfiguration(config)
        }
        let exportItem = NSMenuItem(title: "Export Preset…", action: #selector(exportPreset(_:)), keyEquivalent: "")
        exportItem.target = self
        let importItem = NSMenuItem(title: "Import Preset…", action: #selector(importPreset(_:)), keyEquivalent: "")
        importItem.target = self
        importExportButton.menu?.addItem(exportItem)
        importExportButton.menu?.addItem(importItem)

        presetRow.addArrangedSubview(presetPicker)
        presetRow.addArrangedSubview(newButton)
        presetRow.addArrangedSubview(saveControl)
        presetRow.addArrangedSubview(resetButton)
        presetRow.addArrangedSubview(deleteButton)
        presetRow.addArrangedSubview(importExportButton)
        mainStack.addArrangedSubview(presetRow)

        // Divider above bands
        let topDivider = NSBox()
        topDivider.boxType = .separator
        mainStack.addArrangedSubview(topDivider)
        topDivider.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32).isActive = true

        // Row 2: Sliders area
        slidersContainer = BandDropTarget()
        slidersContainer.orientation = .horizontal
        slidersContainer.alignment = .bottom
        slidersContainer.distribution = .fillEqually
        slidersContainer.spacing = 2
        slidersContainer.translatesAutoresizingMaskIntoConstraints = false
        slidersContainer.setupDropTarget()
        slidersContainer.onReorder = { [weak self] from, to in
            self?.reorderBand(from: from, to: to)
        }

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

        let maxGainLabel = NSTextField(labelWithString: "Max:")
        maxGainLabel.font = .systemFont(ofSize: 11)
        maxGainPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        maxGainPicker.font = .systemFont(ofSize: 11)
        for db: Float in [6, 12, 18, 24] {
            maxGainPicker.addItem(withTitle: "±\(Int(db)) dB")
            maxGainPicker.lastItem?.tag = Int(db)
        }
        maxGainPicker.selectItem(withTag: Int(audioEngine.maxGainDB))
        maxGainPicker.target = self
        maxGainPicker.action = #selector(maxGainChanged(_:))

        bottomRow.addArrangedSubview(eqToggle)
        bottomRow.addArrangedSubview(spacer)
        bottomRow.addArrangedSubview(maxGainLabel)
        bottomRow.addArrangedSubview(maxGainPicker)
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
            let column = DraggableBandColumn()
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 4
            column.bandIndex = i

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

            let maxDB = Double(audioEngine.maxGainDB)
            let slider = NSSlider(value: Double(band.gain), minValue: -maxDB, maxValue: maxDB,
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

            column.setupHandle()
            column.addArrangedSubview(gainLabel)
            column.addArrangedSubview(slider)
            column.addArrangedSubview(freqLabel)
            column.addArrangedSubview(qLabel)
            column.addArrangedSubview(column.dragHandle)

            // Right-click context menu
            let menu = NSMenu()

            if i > 0 {
                let moveLeft = NSMenuItem(title: "Move Left", action: #selector(moveBandLeft(_:)), keyEquivalent: "")
                moveLeft.target = self
                moveLeft.tag = i
                menu.addItem(moveLeft)
            }
            if i < bands.count - 1 {
                let moveRight = NSMenuItem(title: "Move Right", action: #selector(moveBandRight(_:)), keyEquivalent: "")
                moveRight.target = self
                moveRight.tag = i
                menu.addItem(moveRight)
            }
            if menu.items.count > 0 { menu.addItem(.separator()) }

            let deleteItem = NSMenuItem(title: "Delete Band", action: #selector(deleteBandFromMenu(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.tag = i
            let redTitle = NSAttributedString(string: "Delete Band", attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuFont(ofSize: 0)
            ])
            deleteItem.attributedTitle = redTitle
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
        savedPresetSnapshot = audioEngine.activePreset
        isModified = false
        resetButton.isEnabled = false
        populatePresetPicker()
        buildSliders()
        updateDeleteButton()
        updateOutputLabel()
        updateEQToggle()
        clippingCheckbox.state = audioEngine.preventClipping ? .on : .off
        lowLatencyCheckbox.state = audioEngine.lowLatency ? .on : .off
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
        let baseName = "\(audioEngine.activePreset.name) (Custom)"
        let existing = presetStore.allPresets.map { $0.name }
        var forkName = baseName
        if existing.contains(forkName) {
            var n = 2
            while existing.contains("\(baseName) \(n)") { n += 1 }
            forkName = "\(baseName) \(n)"
        }
        let custom = EQPresetData(
            id: UUID(),
            name: forkName,
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

    @objc private func maxGainChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        audioEngine.maxGainDB = Float(item.tag)
        var state = iQualizeState.load()
        state.maxGainDB = audioEngine.maxGainDB
        state.save()
        buildSliders()
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

    private func reorderBand(from: Int, to: Int) {
        guard from != to,
              from < audioEngine.activePreset.bands.count,
              to <= audioEngine.activePreset.bands.count else { return }
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let band = preset.bands.remove(at: from)
        preset.bands.insert(band, at: to)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
    }

    @objc private func moveBandLeft(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index > 0, index < audioEngine.activePreset.bands.count else { return }
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        preset.bands.swapAt(index, index - 1)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
    }

    @objc private func moveBandRight(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < audioEngine.activePreset.bands.count - 1 else { return }
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        preset.bands.swapAt(index, index + 1)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
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
                let maxDB = audioEngine.maxGainDB
                let clamped = min(max(value, -maxDB), maxDB)
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
        populatePresetPicker()
        updateWindowTitle()
    }

    @objc private func newPreset(_ sender: NSButton) {
        let existing = presetStore.allPresets.map { $0.name }
        var n = 1
        while existing.contains("Custom EQ \(n)") { n += 1 }
        let preset = EQPresetData(
            id: UUID(),
            name: "Custom EQ \(n)",
            bands: EQPresetData.flat.bands,
            isBuiltIn: false
        )
        presetStore.saveCustomPreset(preset)
        audioEngine.activePreset = preset
        syncUIToPreset()
        saveState()
    }

    @objc private func saveSegmentClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            savePreset(sender)
        } else {
            let point = NSPoint(x: 0, y: sender.bounds.height + 2)
            saveDropdownMenu.popUp(positioning: nil, at: point, in: sender)
        }
    }

    @objc private func savePreset(_ sender: Any) {
        window?.makeFirstResponder(nil)
        if audioEngine.activePreset.isBuiltIn {
            // Built-in: save as new
            saveAsPreset(sender)
            return
        }
        // Custom preset: save in place
        presetStore.saveCustomPreset(audioEngine.activePreset)
        syncUIToPreset()
        saveState()
    }

    @objc private func saveAsPreset(_ sender: Any) {
        window?.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "Save Preset As"
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

        var name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            let existing = presetStore.allPresets.map { $0.name }
            var n = 1
            while existing.contains("Custom EQ \(n)") { n += 1 }
            name = "Custom EQ \(n)"
        }

        let newPreset = EQPresetData(
            id: UUID(),
            name: name,
            bands: audioEngine.activePreset.bands,
            isBuiltIn: false
        )
        presetStore.saveCustomPreset(newPreset)
        audioEngine.activePreset = newPreset
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

    @objc private func exportPreset(_ sender: NSMenuItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(audioEngine.activePreset.name).iqpreset"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(audioEngine.activePreset)
            try data.write(to: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func importPreset(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            var preset = try JSONDecoder().decode(EQPresetData.self, from: data)
            // Give it a new ID to avoid collisions
            preset = EQPresetData(id: UUID(), name: preset.name, bands: preset.bands, isBuiltIn: false)
            presetStore.saveCustomPreset(preset)
            audioEngine.activePreset = preset
            syncUIToPreset()
            saveState()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func saveState() {
        var state = iQualizeState.load()
        state.selectedPresetID = audioEngine.activePreset.id
        state.save()
    }
}
