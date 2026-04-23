import AppKit
import ServiceManagement

@available(macOS 14.2, *)
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let audioEngine: AudioEngine
    private weak var eqWindowController: EQWindowController?

    private var peakLimiterCheckbox: NSButton!
    private var maxGainPicker: NSPopUpButton!
    private var autoScaleCheckbox: NSButton!
    private var preEqCheckbox: NSButton!
    private var postEqCheckbox: NSButton!
    private var bandwidthModeSegment: NSSegmentedControl!
    private var hideFromDockCheckbox: NSButton!
    private var startAtLoginCheckbox: NSButton!

    init(audioEngine: AudioEngine, eqWindowController: EQWindowController?) {
        self.audioEngine = audioEngine
        self.eqWindowController = eqWindowController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: true
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        let contentView = buildContent()
        window.contentView = contentView
        window.setContentSize(contentView.fittingSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updateEQWindowController(_ controller: EQWindowController?) {
        eqWindowController = controller
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let state = iQualizeState.load()
        peakLimiterCheckbox.state = audioEngine.peakLimiter ? .on : .off
        maxGainPicker.selectItem(withTag: Int(audioEngine.maxGainDB))
        autoScaleCheckbox.state = state.autoScale ? .on : .off
        maxGainPicker.isEnabled = !state.autoScale
        preEqCheckbox.state = state.preEqSpectrumEnabled ? .on : .off
        postEqCheckbox.state = state.postEqSpectrumEnabled ? .on : .off
        bandwidthModeSegment.selectedSegment = state.showBandwidthAsQ ? 0 : 1
    }

    private func buildContent() -> NSView {
        let state = iQualizeState.load()

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        // ── Audio ──
        let audioHeader = makeSectionHeader("Audio")
        mainStack.addArrangedSubview(audioHeader)

        peakLimiterCheckbox = NSButton(checkboxWithTitle: "Peak Limiter",
                                        target: self, action: #selector(togglePeakLimiter(_:)))
        peakLimiterCheckbox.state = audioEngine.peakLimiter ? .on : .off
        mainStack.addArrangedSubview(peakLimiterCheckbox)

        let maxGainRow = NSStackView()
        maxGainRow.orientation = .horizontal
        maxGainRow.spacing = 6

        let maxGainLabel = NSTextField(labelWithString: "Max Gain:")
        maxGainLabel.font = .systemFont(ofSize: 13)
        maxGainRow.addArrangedSubview(maxGainLabel)

        maxGainPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        maxGainPicker.font = .systemFont(ofSize: 13)
        for db: Float in [6, 12, 18, 24] {
            maxGainPicker.addItem(withTitle: "±\(Int(db)) dB")
            maxGainPicker.lastItem?.tag = Int(db)
        }
        maxGainPicker.selectItem(withTag: Int(audioEngine.maxGainDB))
        maxGainPicker.target = self
        maxGainPicker.action = #selector(maxGainChanged(_:))
        maxGainPicker.isEnabled = !state.autoScale
        maxGainRow.addArrangedSubview(maxGainPicker)

        autoScaleCheckbox = NSButton(checkboxWithTitle: "Auto Scale",
                                       target: self, action: #selector(toggleAutoScale(_:)))
        autoScaleCheckbox.state = state.autoScale ? .on : .off
        maxGainRow.addArrangedSubview(autoScaleCheckbox)

        mainStack.addArrangedSubview(maxGainRow)

        // ── Display ──
        let displayHeader = makeSectionHeader("Display")
        mainStack.addArrangedSubview(displayHeader)

        preEqCheckbox = NSButton(checkboxWithTitle: "Pre-EQ Spectrum",
                                   target: self, action: #selector(togglePreEqSpectrum(_:)))
        preEqCheckbox.state = state.preEqSpectrumEnabled ? .on : .off
        mainStack.addArrangedSubview(preEqCheckbox)

        postEqCheckbox = NSButton(checkboxWithTitle: "Post-EQ Spectrum",
                                    target: self, action: #selector(togglePostEqSpectrum(_:)))
        postEqCheckbox.state = state.postEqSpectrumEnabled ? .on : .off
        mainStack.addArrangedSubview(postEqCheckbox)

        let bwRow = NSStackView()
        bwRow.orientation = .horizontal
        bwRow.spacing = 6

        let bwLabel = NSTextField(labelWithString: "Bandwidth:")
        bwLabel.font = .systemFont(ofSize: 13)
        bwRow.addArrangedSubview(bwLabel)

        bandwidthModeSegment = NSSegmentedControl(labels: ["Q", "Oct"], trackingMode: .selectOne,
                                                    target: self, action: #selector(bandwidthModeChanged(_:)))
        bandwidthModeSegment.selectedSegment = state.showBandwidthAsQ ? 0 : 1
        bwRow.addArrangedSubview(bandwidthModeSegment)

        mainStack.addArrangedSubview(bwRow)

        // ── General ──
        let generalHeader = makeSectionHeader("General")
        mainStack.addArrangedSubview(generalHeader)

        hideFromDockCheckbox = NSButton(checkboxWithTitle: "Hide from Dock",
                                          target: self, action: #selector(toggleHideFromDock(_:)))
        hideFromDockCheckbox.state = state.hideFromDock ? .on : .off
        mainStack.addArrangedSubview(hideFromDockCheckbox)

        startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at Login",
                                          target: self, action: #selector(toggleStartAtLogin(_:)))
        startAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        mainStack.addArrangedSubview(startAtLoginCheckbox)

        return mainStack
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    // MARK: - Actions

    @objc private func togglePeakLimiter(_ sender: NSButton) {
        audioEngine.peakLimiter = sender.state == .on
        var state = iQualizeState.load()
        state.peakLimiter = audioEngine.peakLimiter
        state.save()
        eqWindowController?.syncPeakLimiter(audioEngine.peakLimiter)
    }

    @objc private func maxGainChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        audioEngine.maxGainDB = Float(item.tag)
        var state = iQualizeState.load()
        state.maxGainDB = audioEngine.maxGainDB
        state.save()
        eqWindowController?.syncMaxGain(audioEngine.maxGainDB)
    }

    @objc private func toggleAutoScale(_ sender: NSButton) {
        let on = sender.state == .on
        maxGainPicker.isEnabled = !on
        var state = iQualizeState.load()
        state.autoScale = on
        state.save()
        eqWindowController?.syncAutoScale(on)
    }

    @objc private func togglePreEqSpectrum(_ sender: NSButton) {
        let on = sender.state == .on
        var state = iQualizeState.load()
        state.preEqSpectrumEnabled = on
        state.save()
        eqWindowController?.syncPreEqSpectrum(on)
    }

    @objc private func togglePostEqSpectrum(_ sender: NSButton) {
        let on = sender.state == .on
        var state = iQualizeState.load()
        state.postEqSpectrumEnabled = on
        state.save()
        eqWindowController?.syncPostEqSpectrum(on)
    }

    @objc private func bandwidthModeChanged(_ sender: NSSegmentedControl) {
        let asQ = sender.selectedSegment == 0
        var state = iQualizeState.load()
        state.showBandwidthAsQ = asQ
        state.save()
        eqWindowController?.syncBandwidthMode(asQ: asQ)
    }

    @objc private func toggleHideFromDock(_ sender: NSButton) {
        var state = iQualizeState.load()
        state.hideFromDock = sender.state == .on
        state.save()
        NSApp.setActivationPolicy(state.hideFromDock ? .accessory : .regular)
        if !state.hideFromDock {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func toggleStartAtLogin(_ sender: NSButton) {
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
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        var state = iQualizeState.load()
        state.startAtLogin = SMAppService.mainApp.status == .enabled
        state.save()
    }
}
