import AppKit

// MARK: - Custom window for keyboard event interception

@available(macOS 14.2, *)
@MainActor
final class EQWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}

@available(macOS 14.2, *)
@MainActor
final class UnitTextField: NSTextField {
    var onFocus: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?

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

    override func scrollWheel(with event: NSEvent) {
        guard let onScroll else { super.scrollWheel(with: event); return }
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard delta != 0 else { return }
        onScroll(delta > 0 ? 1 : -1)
    }
}

@available(macOS 14.2, *)
@MainActor
final class ScrollableSlider: NSSlider {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard let onScroll else { super.scrollWheel(with: event); return }
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard delta != 0 else { return }
        onScroll(delta > 0 ? 1 : -1)
    }
}

@available(macOS 14.2, *)
@MainActor
final class ClickThroughView: NSView {
    var onClickBackground: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        onClickBackground?()
        super.mouseDown(with: event)
    }
}

// MARK: - Frequency response curve

@available(macOS 14.2, *)
@MainActor
final class FrequencyResponseView: NSView {
    private var bands: [EQBand] = []
    private var maxGainDB: Float = 12
    private var sampleRate: Double = 48000
    private var autoScale: Bool = true

    // Animation state
    private var currentDisplayMax: Double = 12.0
    private var currentDisplayMin: Double = -12.0
    private var targetDisplayMax: Double = 12.0
    private var targetDisplayMin: Double = -12.0
    private var displayGains: [Float] = []  // lerped gains for spline/slider animation
    private var animationTimer: DispatchSourceTimer?

    /// Called each animation frame with interpolated gain values so sliders can be updated.
    var onDisplayGainsChanged: (([Float]) -> Void)?

    /// Called when the animated display range changes, so slider min/max can be updated.
    var onDisplayRangeChanged: ((Double, Double) -> Void)?

    /// When true, draws with transparent background (for use as slider backdrop).
    var isBackdrop = false

    /// Reference slider used to align the curve's gain axis with the slider track.
    weak var referenceSlider: NSSlider?

    /// All band sliders — used to compute column center X at draw time.
    var allSliders: [NSSlider] = []

    func updateBands(_ bands: [EQBand], maxGainDB: Float, sampleRate: Double, autoScale: Bool) {
        let targetGains = bands.map { $0.gain }

        // Resize displayGains to match new band count, lerping instead of snapping
        if displayGains.count != bands.count {
            if displayGains.count < bands.count {
                // New bands: start from 0 and lerp in
                displayGains.append(contentsOf: [Float](repeating: 0, count: bands.count - displayGains.count))
            } else {
                // Removed bands: truncate
                displayGains = Array(displayGains.prefix(bands.count))
            }
        }

        self.bands = bands
        self.maxGainDB = maxGainDB
        self.sampleRate = sampleRate
        self.autoScale = autoScale

        // Start animation if gains differ
        if displayGains != targetGains {
            startAnimationIfNeeded()
        }

        needsDisplay = true
    }

    deinit {
        animationTimer?.cancel()
        animationTimer = nil
    }

    // MARK: - Auto-scale

    private func computeTargetRange(compositeGains: [Double]) -> (min: Double, max: Double) {
        guard autoScale else {
            return (min: Double(-maxGainDB), max: Double(maxGainDB))
        }
        let peakDb = compositeGains.max() ?? 0
        let valleyDb = compositeGains.min() ?? 0

        // Asymmetric: scale top and bottom independently for tight fit.
        // Zero stays at center — gainToY uses split scaling above/below zero.
        var displayMax = ceil(max(abs(peakDb), 1.0) * 1.2)
        var displayMin = -ceil(max(abs(valleyDb), 1.0) * 1.2)

        return (min: displayMin, max: displayMax)
    }

    private func startAnimationIfNeeded() {
        guard animationTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.animationTick()
        }
        timer.resume()
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.cancel()
        animationTimer = nil
    }

    private func animationTick() {
        var converged = true

        // Lerp display range
        let maxDelta = max(abs(targetDisplayMax - currentDisplayMax), abs(targetDisplayMin - currentDisplayMin))
        let rangeFactor = maxDelta > 5.0 ? 0.04 : maxDelta > 2.0 ? 0.07 : 0.10
        currentDisplayMax += (targetDisplayMax - currentDisplayMax) * rangeFactor
        currentDisplayMin += (targetDisplayMin - currentDisplayMin) * rangeFactor

        if abs(currentDisplayMax - targetDisplayMax) > 0.01 ||
           abs(currentDisplayMin - targetDisplayMin) > 0.01 {
            converged = false
        } else {
            currentDisplayMax = targetDisplayMax
            currentDisplayMin = targetDisplayMin
        }

        onDisplayRangeChanged?(currentDisplayMin, currentDisplayMax)

        // Lerp band gains (for spline + slider knob animation)
        // Adaptive: slower for large jumps (preset changes), faster for small tweaks
        let maxGainDelta = zip(displayGains, bands).map { abs($0 - $1.gain) }.max() ?? 0
        let gainFactor: Float = maxGainDelta > 6.0 ? 0.05 : maxGainDelta > 2.0 ? 0.07 : 0.10
        var gainsChanged = false
        for i in 0..<min(displayGains.count, bands.count) {
            let target = bands[i].gain
            let delta = target - displayGains[i]
            if abs(delta) > 0.01 {
                displayGains[i] += delta * gainFactor
                converged = false
                gainsChanged = true
            } else if displayGains[i] != target {
                displayGains[i] = target
                gainsChanged = true
            }
        }

        if gainsChanged {
            onDisplayGainsChanged?(displayGains)
        }

        if converged {
            stopAnimation()
        }
        needsDisplay = true
    }

    // MARK: - Coordinate mapping

    private func freqToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let norm = log10(Double(freq) / 20.0) / 3.0 // log10(20000/20) = 3
        return CGFloat(norm) * width
    }

    private func gainToY(_ gain: Float, height: CGFloat) -> CGFloat {
        let range = currentDisplayMax - currentDisplayMin
        guard range > 0 else { return height / 2.0 }
        let norm = (Double(gain) - currentDisplayMin) / range
        return CGFloat(norm) * height
    }

    private func clampToDisplayRange(_ gain: Float) -> Float {
        min(max(gain, Float(currentDisplayMin)), Float(currentDisplayMax))
    }

    /// Per-band gain contribution using filter-type-appropriate response curves.
    private func bandGain(for band: EQBand, at freq: Float) -> Float {
        let octaves = log2(freq / band.frequency)

        switch band.filterType {
        case .parametric:
            // Bell — gaussian peak/dip centered on frequency
            let sigma = max(band.bandwidth, 0.1) / 2.0
            return band.gain * exp(-0.5 * (octaves / sigma) * (octaves / sigma))

        case .lowShelf:
            // Sigmoid that boosts/cuts everything below frequency
            let slope = 4.0 / max(band.bandwidth, 0.1)
            return band.gain * 0.5 * (1.0 - tanh(slope * octaves))

        case .highShelf:
            // Sigmoid that boosts/cuts everything above frequency
            let slope = 4.0 / max(band.bandwidth, 0.1)
            return band.gain * 0.5 * (1.0 + tanh(slope * octaves))

        case .lowPass:
            // Flat below cutoff, rolls off above — slope scales with Q
            let slope = 2.0 / max(band.bandwidth, 0.1)
            let rolloff = max(octaves, 0) * slope
            return -rolloff * 6.0  // ~6 dB/oct per unit slope

        case .highPass:
            // Rolls off below cutoff, flat above
            let slope = 2.0 / max(band.bandwidth, 0.1)
            let rolloff = max(-octaves, 0) * slope
            return -rolloff * 6.0

        case .bandPass:
            // Kills everything outside the band — inverted gaussian
            let sigma = band.bandwidth / 2.0
            let atten = 1.0 - exp(-0.5 * (octaves / sigma) * (octaves / sigma))
            return -atten * maxGainDB

        case .notch:
            // Narrow surgical dip — tight gaussian, Q×4
            let sigma = band.bandwidth / 8.0  // 4× tighter than bell
            return -maxGainDB * exp(-0.5 * (octaves / sigma) * (octaves / sigma))
        }
    }

    private func compositeGain(at freq: Float) -> Float {
        var total: Float = 0
        for band in bands {
            total += bandGain(for: band, at: freq)
        }
        return total
    }

    /// Catmull-Rom spline through band control points in pixel-X space.
    /// Uses actual column center positions so the curve passes through every handle.
    private func splinePoints(plotRect: CGRect) -> [CGPoint] {
        guard !bands.isEmpty, allSliders.count == bands.count else { return [] }

        // Compute column center X positions from actual slider frames
        let centerXs: [CGFloat] = allSliders.map { slider in
            let center = slider.convert(
                CGPoint(x: slider.bounds.midX, y: 0), to: nil)
            return convert(center, from: nil).x
        }

        // Build control points: (pixelX, gain)
        // Anchor at left/right edges at 0 dB — use displayGains for smooth animation
        var pts: [(x: CGFloat, y: Float)] = [(plotRect.minX, 0)]
        for i in 0..<bands.count {
            let gain = i < displayGains.count ? displayGains[i] : bands[i].gain
            pts.append((centerXs[i], gain))
        }
        pts.append((plotRect.maxX, 0))

        // Sample the Catmull-Rom spline at pixel resolution
        let sampleCount = 200
        var result: [CGPoint] = []

        for s in 0...sampleCount {
            let pixelX = plotRect.minX + CGFloat(s) / CGFloat(sampleCount) * plotRect.width

            // Find segment
            var seg = 0
            for i in 1..<pts.count {
                if pixelX <= pts[i].x { seg = i - 1; break }
                seg = i - 1
            }

            let i0 = max(seg - 1, 0)
            let i1 = seg
            let i2 = min(seg + 1, pts.count - 1)
            let i3 = min(seg + 2, pts.count - 1)

            let p0 = pts[i0], p1 = pts[i1], p2 = pts[i2], p3 = pts[i3]

            let span = p2.x - p1.x
            let t: CGFloat = span > 0 ? (pixelX - p1.x) / span : 0

            let t2 = t * t
            let t3 = t2 * t
            let gain = Float(0.5) * (
                (2 * p1.y) +
                (-p0.y + p2.y) * Float(t) +
                (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * Float(t2) +
                (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * Float(t3)
            )

            let clamped = min(max(gain, -maxGainDB), maxGainDB)
            let y = gainToY(clamped, height: plotRect.height) + plotRect.minY
            result.append(CGPoint(x: pixelX, y: y))
        }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let labelMargin: CGFloat = isBackdrop ? 28 : 0
        let inset: CGFloat = isBackdrop ? 0 : 4
        var plotRect = b.insetBy(dx: inset + labelMargin, dy: inset)

        // In backdrop mode, align the gain axis to the slider track area.
        // Computed here (not in layout()) because the slider lives in a sibling
        // view tree whose layout may not be complete when our layout() runs.
        if isBackdrop, let slider = referenceSlider, let cell = slider.cell as? NSSliderCell {
            // Use current knob rect to get actual knob height, then derive
            // the travel endpoints mathematically (no slider value mutation)
            let knobH = cell.knobRect(flipped: slider.isFlipped).height
            // In slider's own coords (not flipped, Y=0 at bottom):
            // knob center at minValue = knobH/2, at maxValue = height - knobH/2
            let minCenterInSlider = CGPoint(x: 0, y: knobH / 2.0)
            let maxCenterInSlider = CGPoint(x: 0, y: slider.bounds.height - knobH / 2.0)
            let bottomY = convert(slider.convert(minCenterInSlider, to: nil), from: nil).y
            let topY = convert(slider.convert(maxCenterInSlider, to: nil), from: nil).y

            plotRect = CGRect(
                x: plotRect.minX,
                y: min(bottomY, topY),
                width: plotRect.width,
                height: abs(topY - bottomY)
            )
        }

        if !isBackdrop {
            // Standalone mode: draw own background
            let bgPath = NSBezierPath(roundedRect: b, xRadius: 6, yRadius: 6)
            NSColor.controlBackgroundColor.setFill()
            bgPath.fill()
            NSColor.separatorColor.setStroke()
            bgPath.lineWidth = 0.5
            bgPath.stroke()
        }

        ctx.saveGState()
        ctx.clip(to: plotRect)

        let accentColor = NSColor.controlAccentColor

        // ── 1. Grid ──

        // Frequency grid (vertical lines)
        let freqGridLines: [Float] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.04).cgColor)
        ctx.setLineWidth(0.5)
        for freq in freqGridLines {
            let x = freqToX(freq, width: plotRect.width) + plotRect.minX
            ctx.move(to: CGPoint(x: x, y: plotRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        }
        ctx.strokePath()

        // dB grid (horizontal lines) — step adapts to display range
        let displayRange = currentDisplayMax - currentDisplayMin
        let dbStep: Double
        if displayRange <= 4 { dbStep = 1 }
        else if displayRange <= 8 { dbStep = 2 }
        else if displayRange <= 16 { dbStep = 3 }
        else { dbStep = 6 }
        var dbLine = -ceil(currentDisplayMax / dbStep) * dbStep
        while dbLine <= currentDisplayMax + dbStep {
            let y = gainToY(Float(dbLine), height: plotRect.height) + plotRect.minY
            guard y >= plotRect.minY && y <= plotRect.maxY else { dbLine += dbStep; continue }
            if abs(dbLine) < 0.1 {
                // 0 dB line — brighter
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
                ctx.setLineWidth(0.75)
            } else {
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.04).cgColor)
                ctx.setLineWidth(0.5)
            }
            ctx.move(to: CGPoint(x: plotRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            ctx.strokePath()
            dbLine += dbStep
        }

        // ── 2. Biquad computation ──

        let frequencies = BiquadResponse.logFrequencies(count: 512)
        let allCoeffs = bands.map { BiquadResponse.coefficients(for: $0, sampleRate: sampleRate) }

        // Per-band responses
        let perBandGains: [[Double]] = allCoeffs.map { coeffs in
            frequencies.map { coeffs.gainDB(at: $0, sampleRate: sampleRate) }
        }

        // Composite response
        let compositeGains: [Double] = (0..<frequencies.count).map { i in
            perBandGains.reduce(0.0) { $0 + $1[i] }
        }

        // Auto-scale: compute target range and animate toward it
        let (tMin, tMax) = computeTargetRange(compositeGains: compositeGains)
        if tMin != targetDisplayMin || tMax != targetDisplayMax {
            targetDisplayMin = tMin
            targetDisplayMax = tMax
            startAnimationIfNeeded()
        }

        // Map to pixel coordinates
        let compositePts: [CGPoint] = zip(frequencies, compositeGains).map { freq, gain in
            let t = log10(freq / 20.0) / 3.0
            let clamped = clampToDisplayRange(Float(gain))
            let x = CGFloat(t) * plotRect.width + plotRect.minX
            let y = gainToY(clamped, height: plotRect.height) + plotRect.minY
            return CGPoint(x: x, y: y)
        }

        let zeroY = gainToY(0, height: plotRect.height) + plotRect.minY

        // ── 3. Band ghost fills ──

        for bandGains in perBandGains {
            let ghostPath = CGMutablePath()
            var first = true
            for (i, freq) in frequencies.enumerated() {
                let t = log10(freq / 20.0) / 3.0
                let clamped = clampToDisplayRange(Float(bandGains[i]))
                let x = CGFloat(t) * plotRect.width + plotRect.minX
                let y = gainToY(clamped, height: plotRect.height) + plotRect.minY
                if first { ghostPath.move(to: CGPoint(x: x, y: y)); first = false }
                else { ghostPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            // Close to zero line
            let lastT = log10(frequencies.last! / 20.0) / 3.0
            let firstT = log10(frequencies.first! / 20.0) / 3.0
            ghostPath.addLine(to: CGPoint(x: CGFloat(lastT) * plotRect.width + plotRect.minX, y: zeroY))
            ghostPath.addLine(to: CGPoint(x: CGFloat(firstT) * plotRect.width + plotRect.minX, y: zeroY))
            ghostPath.closeSubpath()

            ctx.saveGState()
            ctx.addPath(ghostPath)
            ctx.clip()
            ctx.setFillColor(accentColor.withAlphaComponent(0.035).cgColor)
            ctx.fill(plotRect)
            ctx.restoreGState()
        }

        // ── 4. Composite fill (different opacity for boost vs cut) ──

        if !compositePts.isEmpty {
            let fillPath = CGMutablePath()
            fillPath.move(to: CGPoint(x: compositePts[0].x, y: zeroY))
            for pt in compositePts { fillPath.addLine(to: pt) }
            fillPath.addLine(to: CGPoint(x: compositePts.last!.x, y: zeroY))
            fillPath.closeSubpath()

            ctx.saveGState()
            ctx.addPath(fillPath)
            ctx.clip()
            // Boost region (above zero line)
            ctx.setFillColor(accentColor.withAlphaComponent(0.10).cgColor)
            ctx.fill(CGRect(x: plotRect.minX, y: zeroY,
                            width: plotRect.width, height: plotRect.maxY - zeroY))
            // Cut region (below zero line)
            ctx.setFillColor(accentColor.withAlphaComponent(0.06).cgColor)
            ctx.fill(CGRect(x: plotRect.minX, y: plotRect.minY,
                            width: plotRect.width, height: zeroY - plotRect.minY))
            ctx.restoreGState()
        }

        // ── 5. Composite line ──

        if !compositePts.isEmpty {
            let curvePath = CGMutablePath()
            curvePath.move(to: compositePts[0])
            for pt in compositePts.dropFirst() { curvePath.addLine(to: pt) }
            ctx.setStrokeColor(accentColor.withAlphaComponent(0.65).cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.round)
            ctx.addPath(curvePath)
            ctx.strokePath()
        }

        // ── 6. Anchor dots ──

        if isBackdrop {
            for band in bands {
                let freq = Double(band.frequency)
                let compositeDB = allCoeffs.reduce(0.0) { $0 + $1.gainDB(at: freq, sampleRate: sampleRate) }
                let t = log10(freq / 20.0) / 3.0
                let clamped = clampToDisplayRange(Float(compositeDB))
                let x = CGFloat(t) * plotRect.width + plotRect.minX
                let y = gainToY(clamped, height: plotRect.height) + plotRect.minY

                // Drop line from anchor to zero
                ctx.setStrokeColor(accentColor.withAlphaComponent(0.15).cgColor)
                ctx.setLineWidth(0.75)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x, y: zeroY))
                ctx.strokePath()

                // Outer circle
                let outerR: CGFloat = 4
                let outerRect = CGRect(x: x - outerR, y: y - outerR, width: outerR * 2, height: outerR * 2)
                ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
                ctx.fillEllipse(in: outerRect)
                ctx.setStrokeColor(accentColor.withAlphaComponent(0.60).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: outerRect)

                // Inner dot
                let innerR: CGFloat = 1.5
                let innerRect = CGRect(x: x - innerR, y: y - innerR, width: innerR * 2, height: innerR * 2)
                ctx.setFillColor(accentColor.withAlphaComponent(0.70).cgColor)
                ctx.fillEllipse(in: innerRect)

                // Anchor dB label
                let compositeDBf = Float(compositeDB)
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                ]
                let dbText: String
                if compositeDBf == Float(Int(compositeDBf)) {
                    dbText = String(format: "%+d", Int(compositeDBf))
                } else {
                    dbText = String(format: "%+.1f", compositeDBf)
                }
                let str = NSAttributedString(string: dbText, attributes: labelAttrs)
                let size = str.size()
                var labelX = x + 6
                if labelX + size.width > plotRect.maxX {
                    labelX = x - 6 - size.width
                }
                let labelY = min(max(y + 3, plotRect.minY), plotRect.maxY - size.height)
                str.draw(at: CGPoint(x: labelX, y: labelY))
            }
        }

        // ── 7. Spline (dashed gray, on top) ──

        var curvePoints: [CGPoint]
        if isBackdrop {
            curvePoints = splinePoints(plotRect: plotRect)
        } else {
            let sampleCount = 200
            curvePoints = []
            for i in 0...sampleCount {
                let t = Float(i) / Float(sampleCount)
                let freq = 20.0 * pow(1000.0, t)
                let gain = compositeGain(at: freq)
                let clamped = min(max(gain, -maxGainDB), maxGainDB)
                let x = CGFloat(t) * plotRect.width + plotRect.minX
                let y = gainToY(clamped, height: plotRect.height) + plotRect.minY
                curvePoints.append(CGPoint(x: x, y: y))
            }
        }

        if !curvePoints.isEmpty {
            let splinePath = CGMutablePath()
            splinePath.move(to: curvePoints[0])
            for pt in curvePoints.dropFirst() { splinePath.addLine(to: pt) }
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
            ctx.setLineWidth(isBackdrop ? 0.75 : 1.0)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.addPath(splinePath)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        // ── 8. Band markers (standalone mode only) ──

        if !isBackdrop {
            for band in bands {
                let freq = Double(band.frequency)
                let compositeDB = allCoeffs.isEmpty ? 0.0 :
                    allCoeffs.reduce(0.0) { $0 + $1.gainDB(at: freq, sampleRate: sampleRate) }
                let t = log10(freq / 20.0) / 3.0
                let clamped = clampToDisplayRange(Float(compositeDB))
                let x = CGFloat(t) * plotRect.width + plotRect.minX
                let y = gainToY(clamped, height: plotRect.height) + plotRect.minY

                // Drop line
                ctx.setStrokeColor(accentColor.withAlphaComponent(0.15).cgColor)
                ctx.setLineWidth(0.75)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x, y: zeroY))
                ctx.strokePath()

                // Outer circle
                let outerR: CGFloat = 4
                let outerRect = CGRect(x: x - outerR, y: y - outerR, width: outerR * 2, height: outerR * 2)
                ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
                ctx.fillEllipse(in: outerRect)
                ctx.setStrokeColor(accentColor.withAlphaComponent(0.60).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: outerRect)

                // Inner dot
                let innerR: CGFloat = 1.5
                let innerRect = CGRect(x: x - innerR, y: y - innerR, width: innerR * 2, height: innerR * 2)
                ctx.setFillColor(accentColor.withAlphaComponent(0.70).cgColor)
                ctx.fillEllipse(in: innerRect)

                // Anchor dB label
                let compositeDBf = Float(compositeDB)
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                ]
                let dbText: String
                if compositeDBf == Float(Int(compositeDBf)) {
                    dbText = String(format: "%+d", Int(compositeDBf))
                } else {
                    dbText = String(format: "%+.1f", compositeDBf)
                }
                let str = NSAttributedString(string: dbText, attributes: labelAttrs)
                let size = str.size()
                var labelX = x + 6
                if labelX + size.width > plotRect.maxX {
                    labelX = x - 6 - size.width
                }
                let labelY = min(max(y + 3, plotRect.minY), plotRect.maxY - size.height)
                str.draw(at: CGPoint(x: labelX, y: labelY))
            }
        }

        ctx.restoreGState()

        // ── dB axis labels — drawn in the 16px margins outside the plot clip ──
        if isBackdrop {
            let axisAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.20),
            ]
            let displayMaxInt = Int(round(currentDisplayMax))
            let displayMinInt = Int(round(currentDisplayMin))
            let axisLabels: [(Float, String)] = [
                (Float(currentDisplayMax), "+\(displayMaxInt)"),
                (0, "0"),
                (Float(currentDisplayMin), "\(displayMinInt)"),
            ]
            for (db, text) in axisLabels {
                let y = gainToY(db, height: plotRect.height) + plotRect.minY
                let str = NSAttributedString(string: text, attributes: axisAttrs)
                let size = str.size()
                let centerY = y - size.height / 2.0
                // Left margin: right-aligned within the 16px gap
                str.draw(at: CGPoint(x: plotRect.minX - size.width - 2, y: centerY))
                // Right margin: left-aligned within the 16px gap
                str.draw(at: CGPoint(x: plotRect.maxX + 2, y: centerY))
            }
        }
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
    var onSelect: (() -> Void)?
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
        onSelect?()
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
    private var isDragging = false

    // Hover-reveal add-band buttons
    private var leftHoverButton: NSButton?
    private var rightHoverButton: NSButton?
    private var hoverTrackingArea: NSTrackingArea?

    func setupDropTarget() {
        registerForDraggedTypes([bandDragType, .string])
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        indicator.isHidden = true
        addSubview(indicator)
    }

    func configureHoverButtons(target: AnyObject, leftAction: Selector, rightAction: Selector, canAdd: Bool, sliderCenterY: NSLayoutYAxisAnchor? = nil) {
        leftHoverButton?.removeFromSuperview()
        rightHoverButton?.removeFromSuperview()
        leftHoverButton = nil
        rightHoverButton = nil
        if let old = hoverTrackingArea { removeTrackingArea(old); hoverTrackingArea = nil }

        guard canAdd else { return }

        let makeButton: (Selector) -> NSButton = { action in
            let btn = NSButton(title: "", target: target, action: action)
            btn.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add band")
            btn.imageScaling = .scaleProportionallyUpOrDown
            btn.isBordered = false
            btn.bezelStyle = .regularSquare
            btn.contentTintColor = .controlAccentColor
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.alphaValue = 0
            btn.wantsLayer = true
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 20),
                btn.heightAnchor.constraint(equalToConstant: 20),
            ])
            return btn
        }

        let left = makeButton(leftAction)
        let right = makeButton(rightAction)
        addSubview(left)
        addSubview(right)

        let yAnchor = sliderCenterY ?? centerYAnchor
        NSLayoutConstraint.activate([
            left.centerYAnchor.constraint(equalTo: yAnchor),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -6),
            right.centerYAnchor.constraint(equalTo: yAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 6),
        ])

        leftHoverButton = left
        rightHoverButton = right

        // Set up tracking area
        if let old = hoverTrackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = hoverTrackingArea { removeTrackingArea(old) }
        if leftHoverButton != nil || rightHoverButton != nil {
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverTrackingArea = area
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !isDragging else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let edgeThreshold: CGFloat = 30

        let showLeft = loc.x < edgeThreshold
        let showRight = loc.x > bounds.width - edgeThreshold

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            leftHoverButton?.animator().alphaValue = showLeft ? 1 : 0
            rightHoverButton?.animator().alphaValue = showRight ? 1 : 0
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            leftHoverButton?.animator().alphaValue = 0
            rightHoverButton?.animator().alphaValue = 0
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDragging = true
        leftHoverButton?.alphaValue = 0
        rightHoverButton?.alphaValue = 0
        indicator.isHidden = false
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let loc = convert(sender.draggingLocation, from: nil)
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
        isDragging = false
        indicator.isHidden = true
        dropIndex = nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDragging = false
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
        isDragging = false
        indicator.isHidden = true
        dropIndex = nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow clicks on hover buttons positioned outside our bounds
        for btn in [leftHoverButton, rightHoverButton] {
            guard let btn, btn.alphaValue > 0 else { continue }
            let btnPoint = btn.convert(point, from: superview)
            if btn.bounds.contains(btnPoint) { return btn }
        }
        return super.hitTest(point)
    }
}

@available(macOS 14.2, *)
@MainActor
final class EQWindowController: NSWindowController, NSTextFieldDelegate {
    private let audioEngine: AudioEngine
    private let presetStore: PresetStore

    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var presetPicker: NSPopUpButton!
    private var slidersContainer: BandDropTarget!
    private var sliders: [ScrollableSlider] = []
    private var gainLabels: [UnitTextField] = []
    private var freqLabels: [UnitTextField] = []
    private var qLabels: [UnitTextField] = []
    private var filterTypePickers: [NSPopUpButton] = []
    private var bypassCheckbox: NSButton!
    private var clippingCheckbox: NSButton!
    private var lowLatencyCheckbox: NSButton!
    private var maxGainPicker: NSPopUpButton!
    private var autoScaleCheckbox: NSButton!
    /// Effective max gain: 24 dB when auto-scale is on, otherwise the user-selected value.
    private var effectiveMaxGainDB: Float {
        (autoScaleCheckbox?.state == .on) ? 24 : audioEngine.maxGainDB
    }
    private var outputLabel: NSTextField!
    private var newButton: NSButton!
    private var saveControl: NSSegmentedControl!
    private var saveDropdownMenu: NSMenu!
    private var resetButton: NSButton!
    private var deleteButton: NSButton!
    private var importExportButton: NSButton!
    private var curveView: FrequencyResponseView!

    /// Snapshot of the preset when it was loaded/saved, for reset.
    private var savedPresetSnapshot: EQPresetData?

    /// Tracks whether the user has modified the active preset without saving.
    private var isModified = false

    /// Currently selected band for keyboard navigation (nil = no selection).
    private var selectedBandIndex: Int?

    /// Undo coalescing for rapid keyboard/scroll adjustments.
    private var keyboardAdjustSnapshot: EQPresetData?
    private var keyboardCoalesceTimer: Timer?

    init(audioEngine: AudioEngine, presetStore: PresetStore) {
        self.audioEngine = audioEngine
        self.presetStore = presetStore

        let window = EQWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "iQualize"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 420)

        super.init(window: window)

        setupUI()
        syncUIToPreset()

        // Don't auto-focus any input on open
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }

        // Keyboard shortcuts for band adjustment
        window.onKeyDown = { [weak self] event in
            guard let self else { return false }
            if self.window?.firstResponder is NSTextView { return false }

            let bands = self.audioEngine.activePreset.bands
            guard !bands.isEmpty else { return false }

            switch event.keyCode {
            case 126: // Arrow Up — gain +0.5 dB
                guard self.selectedBandIndex != nil else { return false }
                self.adjustGainViaKeyboard(delta: +0.5)
                return true
            case 125: // Arrow Down — gain -0.5 dB
                guard self.selectedBandIndex != nil else { return false }
                self.adjustGainViaKeyboard(delta: -0.5)
                return true
            case 124: // Arrow Right — frequency up
                guard self.selectedBandIndex != nil else { return false }
                self.adjustFrequencyViaKeyboard(up: true)
                return true
            case 123: // Arrow Left — frequency down
                guard self.selectedBandIndex != nil else { return false }
                self.adjustFrequencyViaKeyboard(up: false)
                return true
            case 48: // Tab
                let forward = !event.modifierFlags.contains(.shift)
                self.moveBandSelection(forward: forward)
                return true
            default:
                return false
            }
        }

        let previousCallback = audioEngine.onStateChange
        audioEngine.onStateChange = { [weak self] in
            previousCallback?()
            self?.updateOutputLabel()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Setup

    private func setupUI() {
        let clickView = ClickThroughView()
        clickView.onClickBackground = { [weak self] in
            self?.selectBand(nil)
        }
        window?.contentView = clickView
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
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
        importExportButton = NSButton(frame: .zero)
        importExportButton.bezelStyle = .rounded
        importExportButton.isBordered = true
        importExportButton.title = ""
        if let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "More") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            importExportButton.image = gearImage.withSymbolConfiguration(config)
        }
        importExportButton.target = self
        importExportButton.action = #selector(showGearMenu(_:))

        let gearMenu = NSMenu()
        let exportItem = NSMenuItem(title: "Export Preset…", action: #selector(exportPreset(_:)), keyEquivalent: "")
        exportItem.target = self
        let importItem = NSMenuItem(title: "Import Preset…", action: #selector(importPreset(_:)), keyEquivalent: "")
        importItem.target = self
        gearMenu.addItem(exportItem)
        gearMenu.addItem(importItem)
        importExportButton.menu = gearMenu

        // Undo/Redo buttons
        undoButton = NSButton(frame: .zero)
        undoButton.bezelStyle = .rounded
        undoButton.isBordered = true
        undoButton.title = ""
        undoButton.toolTip = "Undo"
        undoButton.isEnabled = false
        if let undoImage = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            undoButton.image = undoImage.withSymbolConfiguration(config)
        }
        undoButton.target = self
        undoButton.action = #selector(undoAction(_:))

        redoButton = NSButton(frame: .zero)
        redoButton.bezelStyle = .rounded
        redoButton.isBordered = true
        redoButton.title = ""
        redoButton.toolTip = "Redo"
        redoButton.isEnabled = false
        if let redoImage = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            redoButton.image = redoImage.withSymbolConfiguration(config)
        }
        redoButton.target = self
        redoButton.action = #selector(redoAction(_:))

        presetRow.addArrangedSubview(undoButton)
        presetRow.addArrangedSubview(redoButton)
        presetRow.addArrangedSubview(presetPicker)
        presetRow.addArrangedSubview(newButton)
        presetRow.addArrangedSubview(saveControl)
        presetRow.addArrangedSubview(resetButton)
        presetRow.addArrangedSubview(deleteButton)
        presetRow.addArrangedSubview(importExportButton)
        mainStack.addArrangedSubview(presetRow)
        presetRow.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 16).isActive = true
        presetRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -16).isActive = true

        // Divider above bands
        let topDivider = NSBox()
        topDivider.boxType = .separator
        mainStack.addArrangedSubview(topDivider)
        topDivider.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 16).isActive = true
        topDivider.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -16).isActive = true

        // Row 2: Sliders area with response curve as backdrop
        slidersContainer = BandDropTarget()
        slidersContainer.orientation = .horizontal
        slidersContainer.alignment = .bottom
        slidersContainer.distribution = .fill
        slidersContainer.spacing = 8
        slidersContainer.translatesAutoresizingMaskIntoConstraints = false
        slidersContainer.setupDropTarget()
        slidersContainer.onReorder = { [weak self] from, to in
            self?.reorderBand(from: from, to: to)
        }

        // Wrapper view: curve as background, sliders on top
        let bandsWrapper = NSView()
        bandsWrapper.translatesAutoresizingMaskIntoConstraints = false

        curveView = FrequencyResponseView()
        curveView.isBackdrop = true
        curveView.translatesAutoresizingMaskIntoConstraints = false
        curveView.onDisplayGainsChanged = { [weak self] gains in
            guard let self else { return }
            for (i, gain) in gains.enumerated() where i < self.sliders.count {
                self.sliders[i].doubleValue = Double(gain)
                // Show interpolated gain in label during animation
                let g = gain
                if g == 0 {
                    self.gainLabels[i].stringValue = "0 dB"
                } else if abs(g - Float(Int(g))) < 0.05 {
                    self.gainLabels[i].stringValue = String(format: "%+d dB", Int(roundf(g)))
                } else {
                    self.gainLabels[i].stringValue = String(format: "%+.1f dB", g)
                }
            }
        }
        curveView.onDisplayRangeChanged = { [weak self] displayMin, displayMax in
            guard let self else { return }
            for slider in self.sliders {
                slider.minValue = displayMin
                slider.maxValue = displayMax
            }
        }

        bandsWrapper.addSubview(curveView)
        bandsWrapper.addSubview(slidersContainer)

        // Pin curve to fill the wrapper
        curveView.leadingAnchor.constraint(equalTo: bandsWrapper.leadingAnchor, constant: -28).isActive = true
        curveView.trailingAnchor.constraint(equalTo: bandsWrapper.trailingAnchor, constant: 28).isActive = true
        curveView.topAnchor.constraint(equalTo: bandsWrapper.topAnchor).isActive = true
        curveView.bottomAnchor.constraint(equalTo: bandsWrapper.bottomAnchor).isActive = true

        // Pin sliders to fill the wrapper (on top of curve)
        slidersContainer.leadingAnchor.constraint(equalTo: bandsWrapper.leadingAnchor).isActive = true
        slidersContainer.trailingAnchor.constraint(equalTo: bandsWrapper.trailingAnchor).isActive = true
        slidersContainer.topAnchor.constraint(equalTo: bandsWrapper.topAnchor).isActive = true
        slidersContainer.bottomAnchor.constraint(equalTo: bandsWrapper.bottomAnchor).isActive = true

        mainStack.addArrangedSubview(bandsWrapper)
        bandsWrapper.leadingAnchor.constraint(greaterThanOrEqualTo: mainStack.leadingAnchor, constant: 28).isActive = true
        bandsWrapper.trailingAnchor.constraint(lessThanOrEqualTo: mainStack.trailingAnchor, constant: -28).isActive = true

        // Divider below bands
        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator
        mainStack.addArrangedSubview(bottomDivider)
        bottomDivider.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 16).isActive = true
        bottomDivider.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -16).isActive = true

        // Row 3: Bottom bar — EQ Enabled (left) + Prevent Clipping (right)
        bypassCheckbox = NSButton(checkboxWithTitle: "Bypass",
                                    target: self, action: #selector(toggleBypass(_:)))
        bypassCheckbox.state = audioEngine.bypassed ? .on : .off

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

        autoScaleCheckbox = NSButton(checkboxWithTitle: "Auto",
                                       target: self, action: #selector(toggleAutoScale(_:)))
        let autoScaleOn = iQualizeState.load().autoScale
        autoScaleCheckbox.state = autoScaleOn ? .on : .off
        maxGainPicker.isEnabled = !autoScaleOn

        bottomRow.addArrangedSubview(bypassCheckbox)
        bottomRow.addArrangedSubview(spacer)
        bottomRow.addArrangedSubview(maxGainLabel)
        bottomRow.addArrangedSubview(maxGainPicker)
        bottomRow.addArrangedSubview(autoScaleCheckbox)
        bottomRow.addArrangedSubview(lowLatencyCheckbox)
        bottomRow.addArrangedSubview(clippingCheckbox)

        mainStack.addArrangedSubview(bottomRow)
        bottomRow.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 16).isActive = true
        bottomRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -16).isActive = true

        // Row 5: Output device label
        outputLabel = NSTextField(labelWithString: "Output: \(audioEngine.outputDeviceName)")
        outputLabel.textColor = .secondaryLabelColor
        outputLabel.font = .systemFont(ofSize: 11)
        mainStack.addArrangedSubview(outputLabel)
    }

    // MARK: - Slider Building

    private func buildSliders() {
        let previousSelection = selectedBandIndex
        selectedBandIndex = nil

        for view in slidersContainer.arrangedSubviews {
            slidersContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        sliders.removeAll()
        gainLabels.removeAll()
        freqLabels.removeAll()
        qLabels.removeAll()
        filterTypePickers.removeAll()

        let bands = audioEngine.activePreset.bands
        let canAdd = bands.count < EQPresetData.maxBandCount

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
                self.selectBand(nil)
                gainLabel.stringValue = Self.formatRawFloat(self.audioEngine.activePreset.bands[i].gain)
            }
            gainLabel.onScroll = { [weak self] direction in
                self?.scrollAdjustGain(at: i, direction: direction)
            }
            gainLabels.append(gainLabel)

            let maxDB = Double(effectiveMaxGainDB)
            let slider = ScrollableSlider(value: Double(band.gain), minValue: -maxDB, maxValue: maxDB,
                                  target: self, action: #selector(sliderMoved(_:)))
            slider.isVertical = true
            slider.numberOfTickMarks = 25
            slider.allowsTickMarkValuesOnly = false
            slider.tag = i
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.heightAnchor.constraint(equalToConstant: 180).isActive = true
            slider.onScroll = { [weak self] direction in
                self?.scrollAdjustGain(at: i, direction: direction)
            }

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
                self.selectBand(nil)
                freqLabel.stringValue = Self.formatRawFloat(self.audioEngine.activePreset.bands[i].frequency)
            }
            freqLabel.onScroll = { [weak self] direction in
                self?.scrollAdjustFrequency(at: i, direction: direction)
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
                self.selectBand(nil)
                qLabel.stringValue = Self.formatRawFloat(self.audioEngine.activePreset.bands[i].bandwidth)
            }
            qLabel.onScroll = { [weak self] direction in
                self?.scrollAdjustBandwidth(at: i, direction: direction)
            }
            qLabels.append(qLabel)

            let typePicker = NSPopUpButton(frame: .zero, pullsDown: false)
            typePicker.font = .systemFont(ofSize: 9)
            typePicker.controlSize = .small
            typePicker.tag = i
            for ft in FilterType.allCases {
                typePicker.addItem(withTitle: ft.displayName)
                typePicker.lastItem?.representedObject = ft
            }
            if let idx = FilterType.allCases.firstIndex(of: band.filterType) {
                typePicker.selectItem(at: idx)
            }
            typePicker.target = self
            typePicker.action = #selector(filterTypeChanged(_:))
            filterTypePickers.append(typePicker)

            column.onSelect = { [weak self] in
                self?.window?.makeFirstResponder(nil)
                self?.selectBand(i)
            }
            column.setupHandle()
            column.addArrangedSubview(gainLabel)
            column.addArrangedSubview(slider)
            column.addArrangedSubview(freqLabel)
            column.addArrangedSubview(qLabel)
            column.addArrangedSubview(typePicker)
            column.addArrangedSubview(column.dragHandle)

            // Right-click context menu
            let menu = NSMenu()

            if canAdd {
                let addLeft = NSMenuItem(title: "Add Band to Left", action: #selector(addBandAtIndex(_:)), keyEquivalent: "")
                addLeft.target = self
                addLeft.tag = i
                menu.addItem(addLeft)

                let addRight = NSMenuItem(title: "Add Band to Right", action: #selector(addBandAtIndex(_:)), keyEquivalent: "")
                addRight.target = self
                addRight.tag = -(i + 1) // negative tag encodes "insert after index i"
                menu.addItem(addRight)

                let addSuggested = NSMenuItem(title: "Add Suggested Band", action: #selector(addSuggestedBand(_:)), keyEquivalent: "")
                addSuggested.target = self
                menu.addItem(addSuggested)

                menu.addItem(.separator())
            }

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

            // Make all band columns equal width
            if let firstColumn = slidersContainer.arrangedSubviews.first(where: { $0 is DraggableBandColumn }) as? DraggableBandColumn, firstColumn !== column {
                column.widthAnchor.constraint(equalTo: firstColumn.widthAnchor).isActive = true
            }
        }

        // Configure hover-reveal add-band buttons
        slidersContainer.configureHoverButtons(
            target: self,
            leftAction: #selector(addBandLeft(_:)),
            rightAction: #selector(addBandRight(_:)),
            canAdd: canAdd,
            sliderCenterY: sliders.first?.centerYAnchor
        )

        let bandsWidth = CGFloat(bands.count * 40)
        if let window = self.window {
            var frame = window.frame
            let newWidth = max(bandsWidth, window.minSize.width)
            frame.size.width = newWidth
            window.setFrame(frame, display: true, animate: false)
        }

        // Restore band selection after rebuild
        let bandCount = bands.count
        if let prev = previousSelection, prev < bandCount {
            selectBand(prev)
        } else if previousSelection != nil, bandCount > 0 {
            selectBand(bandCount - 1)
        }

        curveView.referenceSlider = sliders.first
        curveView.allSliders = sliders
        // Force layout so slider frames are valid before drawing the curve
        window?.layoutIfNeeded()
        updateCurveView()
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
        bypassCheckbox.state = audioEngine.bypassed ? .on : .off
        clippingCheckbox.state = audioEngine.preventClipping ? .on : .off
        lowLatencyCheckbox.state = audioEngine.lowLatency ? .on : .off
        let autoOn = iQualizeState.load().autoScale
        autoScaleCheckbox.state = autoOn ? .on : .off
        maxGainPicker.isEnabled = !autoOn
        updateWindowTitle()
        updateCurveView()
    }

    private func updateCurveView() {
        curveView.updateBands(audioEngine.activePreset.bands, maxGainDB: effectiveMaxGainDB, sampleRate: audioEngine.outputSampleRate, autoScale: autoScaleCheckbox.state == .on)
    }

    private func populatePresetPicker() {
        presetPicker.removeAllItems()
        for preset in presetStore.allPresets {
            let title = preset.isBuiltIn ? "\(preset.name) (Built-in)" : preset.name
            presetPicker.addItem(withTitle: title)
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
        updateUndoRedoButtons()
    }

    private func updateUndoRedoButtons() {
        let um = window?.undoManager
        undoButton.isEnabled = um?.canUndo ?? false
        redoButton.isEnabled = um?.canRedo ?? false
    }

    // MARK: - Undo/Redo

    @objc private func undoAction(_ sender: NSButton) {
        window?.undoManager?.undo()
        updateUndoRedoButtons()
    }

    @objc private func redoAction(_ sender: NSButton) {
        window?.undoManager?.redo()
        updateUndoRedoButtons()
    }

    /// Snapshot taken at the start of a slider drag (coalesced into one undo)
    private var sliderDragSnapshot: EQPresetData?

    /// Register an undo action that restores the preset to `oldPreset`.
    private func registerUndo(_ actionName: String, oldPreset: EQPresetData) {
        guard let undoManager = window?.undoManager else { return }
        let currentPreset = audioEngine.activePreset
        undoManager.registerUndo(withTarget: self) { [weak self] target in
            guard let self else { return }
            let redoPreset = self.audioEngine.activePreset
            self.audioEngine.activePreset = oldPreset
            self.buildSliders()
            if oldPreset == self.savedPresetSnapshot {
                self.isModified = false
                self.resetButton.isEnabled = false
                self.populatePresetPicker()
                self.updateWindowTitle()
            } else {
                self.markModified()
            }
            self.registerUndo(actionName, oldPreset: redoPreset)
            // Defer button update until after undo manager finishes processing
            DispatchQueue.main.async { [weak self] in
                self?.updateUndoRedoButtons()
            }
        }
        undoManager.setActionName(actionName)
        updateUndoRedoButtons()
    }

    private func updateWindowTitle() {
        let name = audioEngine.activePreset.name
        window?.title = isModified ? "iQualize — \(name)*" : "iQualize — \(name)"
    }

    // MARK: - Band Selection & Keyboard Navigation

    private func selectBand(_ index: Int?) {
        let oldIndex = selectedBandIndex
        selectedBandIndex = index
        if let old = oldIndex { updateBandSelectionVisual(old, selected: false) }
        if let idx = index { updateBandSelectionVisual(idx, selected: true) }
    }

    private func updateBandSelectionVisual(_ index: Int, selected: Bool) {
        let columns = slidersContainer.arrangedSubviews.compactMap { $0 as? DraggableBandColumn }
        guard index < columns.count else { return }
        let col = columns[index]
        col.wantsLayer = true
        if selected {
            col.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            col.layer?.cornerRadius = 6
        } else {
            col.layer?.backgroundColor = nil
        }
    }

    private func moveBandSelection(forward: Bool) {
        let count = audioEngine.activePreset.bands.count
        guard count > 0 else { return }

        let newIndex: Int
        if let current = selectedBandIndex {
            newIndex = forward ? (current + 1) % count : (current - 1 + count) % count
        } else {
            newIndex = forward ? 0 : count - 1
        }
        selectBand(newIndex)
    }

    private func beginKeyboardAdjustIfNeeded() {
        if keyboardAdjustSnapshot == nil {
            keyboardAdjustSnapshot = audioEngine.activePreset
        }
        keyboardCoalesceTimer?.invalidate()
        keyboardCoalesceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.commitKeyboardAdjust()
            }
        }
    }

    private func commitKeyboardAdjust() {
        guard let snapshot = keyboardAdjustSnapshot else { return }
        keyboardCoalesceTimer?.invalidate()
        keyboardCoalesceTimer = nil
        if audioEngine.activePreset != snapshot {
            registerUndo("Adjust EQ", oldPreset: snapshot)
        }
        keyboardAdjustSnapshot = nil
    }

    private func adjustGainViaKeyboard(delta: Float) {
        guard let index = selectedBandIndex,
              index < audioEngine.activePreset.bands.count else { return }
        beginKeyboardAdjustIfNeeded()
        forkIfBuiltIn()

        var preset = audioEngine.activePreset
        let maxDB = audioEngine.maxGainDB
        let newGain = min(max(preset.bands[index].gain + delta, -maxDB), maxDB)
        guard newGain != preset.bands[index].gain else { return }

        preset.bands[index].gain = newGain
        audioEngine.activePreset = preset
        sliders[index].doubleValue = Double(newGain)
        gainLabels[index].stringValue = preset.bands[index].gainLabel
        markModified()
        updateCurveView()
    }

    private func adjustFrequencyViaKeyboard(up: Bool) {
        guard let index = selectedBandIndex,
              index < audioEngine.activePreset.bands.count else { return }
        beginKeyboardAdjustIfNeeded()
        forkIfBuiltIn()

        var preset = audioEngine.activePreset
        let semitone: Float = pow(2.0, 1.0 / 12.0)
        let factor = up ? semitone : (1.0 / semitone)
        let newFreq = min(max(preset.bands[index].frequency * factor, 20), 20000)

        preset.bands[index].frequency = newFreq
        audioEngine.activePreset = preset
        freqLabels[index].stringValue = preset.bands[index].frequencyLabel
        markModified()
        updateCurveView()
    }

    // MARK: - Scroll Wheel Adjustments

    private func scrollAdjustGain(at index: Int, direction: CGFloat) {
        guard index < audioEngine.activePreset.bands.count else { return }
        beginKeyboardAdjustIfNeeded()
        forkIfBuiltIn()

        var preset = audioEngine.activePreset
        let maxDB = audioEngine.maxGainDB
        let delta: Float = direction > 0 ? 0.5 : -0.5
        let newGain = min(max(preset.bands[index].gain + delta, -maxDB), maxDB)
        guard newGain != preset.bands[index].gain else { return }

        preset.bands[index].gain = newGain
        audioEngine.activePreset = preset
        sliders[index].doubleValue = Double(newGain)
        gainLabels[index].stringValue = preset.bands[index].gainLabel
        markModified()
        updateCurveView()
    }

    private func scrollAdjustFrequency(at index: Int, direction: CGFloat) {
        guard index < audioEngine.activePreset.bands.count else { return }
        beginKeyboardAdjustIfNeeded()
        forkIfBuiltIn()

        var preset = audioEngine.activePreset
        let semitone: Float = pow(2.0, 1.0 / 12.0)
        let factor = direction > 0 ? semitone : (1.0 / semitone)
        let newFreq = min(max(preset.bands[index].frequency * factor, 20), 20000)

        preset.bands[index].frequency = newFreq
        audioEngine.activePreset = preset
        freqLabels[index].stringValue = preset.bands[index].frequencyLabel
        markModified()
        updateCurveView()
    }

    private func scrollAdjustBandwidth(at index: Int, direction: CGFloat) {
        guard index < audioEngine.activePreset.bands.count else { return }
        beginKeyboardAdjustIfNeeded()
        forkIfBuiltIn()

        var preset = audioEngine.activePreset
        let delta: Float = direction > 0 ? 0.1 : -0.1
        let newQ = min(max(preset.bands[index].bandwidth + delta, 0.1), 10)
        guard newQ != preset.bands[index].bandwidth else { return }

        preset.bands[index].bandwidth = newQ
        audioEngine.activePreset = preset
        qLabels[index].stringValue = preset.bands[index].bandwidthLabel
        markModified()
        updateCurveView()
    }

    // MARK: - Actions

    @objc private func toggleBypass(_ sender: NSButton) {
        audioEngine.bypassed = sender.state == .on
        var state = iQualizeState.load()
        state.bypassed = audioEngine.bypassed
        state.save()
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

    @objc private func toggleAutoScale(_ sender: NSButton) {
        let on = sender.state == .on
        var state = iQualizeState.load()
        state.autoScale = on
        state.save()
        maxGainPicker.isEnabled = !on
        updateCurveView()
    }

    @objc private func addBandAtIndex(_ sender: NSMenuItem) {
        guard audioEngine.activePreset.bands.count < EQPresetData.maxBandCount else { return }
        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset

        let insertionIndex: Int
        if sender.tag >= 0 {
            // "Add Band to Left" — insert at this index
            insertionIndex = sender.tag
        } else {
            // "Add Band to Right" — negative tag encodes -(originalIndex + 1), insert after
            insertionIndex = (-sender.tag - 1) + 1
        }

        let clampedIndex = min(insertionIndex, preset.bands.count)
        // Use the band the user clicked as the reference (for "right", look back one index)
        let refIndex = sender.tag >= 0 ? clampedIndex : max(0, clampedIndex - 1)
        let reference = refIndex < preset.bands.count ? preset.bands[refIndex] : (preset.bands.last ?? EQBand(frequency: 1000, gain: 0))
        preset.bands.insert(EQBand(frequency: reference.frequency, gain: reference.gain, bandwidth: reference.bandwidth, filterType: reference.filterType), at: clampedIndex)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Add Band", oldPreset: oldPreset)
    }

    private func reorderBand(from: Int, to: Int) {
        guard from != to,
              from < audioEngine.activePreset.bands.count,
              to <= audioEngine.activePreset.bands.count else { return }
        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let band = preset.bands.remove(at: from)
        preset.bands.insert(band, at: to)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Reorder Band", oldPreset: oldPreset)
    }

    @objc private func moveBandLeft(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index > 0, index < audioEngine.activePreset.bands.count else { return }
        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        preset.bands.swapAt(index, index - 1)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Move Band Left", oldPreset: oldPreset)
    }

    @objc private func moveBandRight(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < audioEngine.activePreset.bands.count - 1 else { return }
        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        preset.bands.swapAt(index, index + 1)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Move Band Right", oldPreset: oldPreset)
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

        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        preset.bands.remove(at: index)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Delete Band", oldPreset: oldPreset)
    }

    @objc private func addBandLeft(_ sender: Any) {
        guard audioEngine.activePreset.bands.count < EQPresetData.maxBandCount else { return }
        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let leftmost = preset.bands.first ?? EQBand(frequency: 100, gain: 0)
        preset.bands.insert(EQBand(frequency: leftmost.frequency, gain: leftmost.gain, bandwidth: leftmost.bandwidth, filterType: leftmost.filterType), at: 0)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Add Band", oldPreset: oldPreset)
    }

    @objc private func addBandRight(_ sender: Any) {
        guard audioEngine.activePreset.bands.count < EQPresetData.maxBandCount else { return }
        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let rightmost = preset.bands.last ?? EQBand(frequency: 1000, gain: 0)
        preset.bands.append(EQBand(frequency: rightmost.frequency, gain: rightmost.gain, bandwidth: rightmost.bandwidth, filterType: rightmost.filterType))
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Add Band", oldPreset: oldPreset)
    }

    @objc private func addSuggestedBand(_ sender: NSMenuItem) {
        guard audioEngine.activePreset.bands.count < EQPresetData.maxBandCount else { return }
        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        let freq = preset.suggestNewBandFrequency()
        let newBand = EQBand(frequency: freq, gain: 0, bandwidth: 1.0)
        let insertIndex = preset.bands.firstIndex(where: { $0.frequency > freq }) ?? preset.bands.count
        preset.bands.insert(newBand, at: insertIndex)
        audioEngine.activePreset = preset
        buildSliders()
        markModified()
        registerUndo("Add Band", oldPreset: oldPreset)
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
                let maxDB = effectiveMaxGainDB
                let clamped = min(max(value, -maxDB), maxDB)
                if clamped != band.gain {
                    let oldPreset = audioEngine.activePreset
                    forkIfBuiltIn()
                    var preset = audioEngine.activePreset
                    preset.bands[index].gain = clamped
                    audioEngine.activePreset = preset
                    sliders[index].doubleValue = Double(clamped)
                    markModified()
                    registerUndo("Change Gain", oldPreset: oldPreset)
                }
            }
            field.stringValue = audioEngine.activePreset.bands[index].gainLabel
        } else if freqLabels.contains(field) {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if let value = Float(text) {
                let clamped = min(max(value, 20), 20000)
                if clamped != band.frequency {
                    let oldPreset = audioEngine.activePreset
                    forkIfBuiltIn()
                    var preset = audioEngine.activePreset
                    preset.bands[index].frequency = clamped
                    audioEngine.activePreset = preset
                    markModified()
                    registerUndo("Change Frequency", oldPreset: oldPreset)
                }
            }
            field.stringValue = audioEngine.activePreset.bands[index].frequencyLabel
        } else if qLabels.contains(field) {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if let value = Float(text), value > 0 {
                let clamped = min(max(value, 0.1), 10)
                if clamped != band.bandwidth {
                    let oldPreset = audioEngine.activePreset
                    forkIfBuiltIn()
                    var preset = audioEngine.activePreset
                    preset.bands[index].bandwidth = clamped
                    audioEngine.activePreset = preset
                    markModified()
                    registerUndo("Change Bandwidth", oldPreset: oldPreset)
                }
            }
            field.stringValue = audioEngine.activePreset.bands[index].bandwidthLabel
        }
        updateCurveView()
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

        // Snapshot at drag start for coalesced undo
        if sliderDragSnapshot == nil {
            sliderDragSnapshot = audioEngine.activePreset
        }

        forkIfBuiltIn()
        let gain = Float(sender.doubleValue)

        var preset = audioEngine.activePreset
        preset.bands[index].gain = gain
        audioEngine.activePreset = preset

        gainLabels[index].stringValue = preset.bands[index].gainLabel
        updateCurveView()
        markModified()

        // Register undo when drag ends (mouse up)
        let event = NSApp.currentEvent
        if event?.type == .leftMouseUp, let snapshot = sliderDragSnapshot {
            registerUndo("Adjust Gain", oldPreset: snapshot)
            sliderDragSnapshot = nil
        }
    }

    @objc private func filterTypeChanged(_ sender: NSPopUpButton) {
        let index = sender.tag
        guard index < audioEngine.activePreset.bands.count,
              let selectedType = sender.selectedItem?.representedObject as? FilterType else { return }

        let band = audioEngine.activePreset.bands[index]
        guard selectedType != band.filterType else { return }

        let oldPreset = audioEngine.activePreset
        forkIfBuiltIn()
        var preset = audioEngine.activePreset
        preset.bands[index].filterType = selectedType
        audioEngine.activePreset = preset
        updateCurveView()
        markModified()
        registerUndo("Change Filter Type", oldPreset: oldPreset)
    }

    @objc private func resetPreset(_ sender: NSButton) {
        guard let snapshot = savedPresetSnapshot else { return }
        audioEngine.activePreset = snapshot

        buildSliders()
        isModified = false
        resetButton.isEnabled = false
        populatePresetPicker()
        updateWindowTitle()
        window?.undoManager?.removeAllActions()
        updateUndoRedoButtons()
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

    @objc private func showGearMenu(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func exportPreset(_ sender: Any) {
        // Use osascript to show a native save dialog — reliable regardless of app policy
        let name = audioEngine.activePreset.name
        let script = """
            set f to POSIX path of (choose file name with prompt "Export Preset" default name "\(name).iqpreset")
            return f
            """
        guard let path = runAppleScript(script) else { return }
        let url = URL(fileURLWithPath: path)
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

    @objc private func importPreset(_ sender: Any) {
        // Use osascript to show a native open dialog with multiple selection
        let script = """
            set fileList to choose file of type {"json", "iqpreset"} with prompt "Import Presets" with multiple selections allowed
            set output to ""
            repeat with f in fileList
                set output to output & POSIX path of f & linefeed
            end repeat
            return output
            """
        guard let output = runAppleScript(script), !output.isEmpty else { return }
        let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        var lastImported: EQPresetData?
        var importCount = 0
        var skipCount = 0

        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(EQPresetData.self, from: data)
                var importName = decoded.name

                // Show import dialog with name field
                let customNames = Set(presetStore.customPresets.map(\.name))
                let nameExists = customNames.contains(importName)

                let alert = NSAlert()
                alert.messageText = nameExists
                    ? "A preset named \"\(importName)\" already exists."
                    : "Import \"\(importName)\""
                alert.informativeText = "You can change the preset name before importing."
                alert.addButton(withTitle: nameExists ? "Overwrite" : "Import")
                alert.addButton(withTitle: "Skip")

                let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
                nameField.stringValue = importName
                nameField.isEditable = true
                nameField.isSelectable = true
                alert.accessoryView = nameField
                alert.window.initialFirstResponder = nameField

                // Dynamically update button label as user types
                let actionButton = alert.buttons[0]
                let observer = NotificationCenter.default.addObserver(
                    forName: NSControl.textDidChangeNotification,
                    object: nameField, queue: .main
                ) { _ in
                    let current = nameField.stringValue.trimmingCharacters(in: .whitespaces)
                    actionButton.title = customNames.contains(current) ? "Overwrite" : "Import"
                }

                let response = alert.runModal()
                NotificationCenter.default.removeObserver(observer)
                if response == .alertSecondButtonReturn {
                    skipCount += 1
                    continue // Skip
                }

                let finalName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
                if finalName.isEmpty {
                    skipCount += 1
                    continue
                }
                importName = finalName

                // If the final name matches an existing preset, confirm overwrite
                if let existing = presetStore.customPresets.first(where: { $0.name == importName }) {
                    let confirm = NSAlert()
                    confirm.messageText = "Overwrite \"\(importName)\"?"
                    confirm.informativeText = "This will replace the existing preset with the imported one."
                    confirm.addButton(withTitle: "Overwrite")
                    confirm.addButton(withTitle: "Cancel")
                    confirm.alertStyle = .warning

                    if confirm.runModal() != .alertFirstButtonReturn {
                        skipCount += 1
                        continue
                    }
                    presetStore.deleteCustomPreset(id: existing.id)
                }

                let preset = EQPresetData(id: UUID(), name: importName, bands: decoded.bands, isBuiltIn: false)
                presetStore.saveCustomPreset(preset)
                lastImported = preset
                importCount += 1
            } catch {
                let alert = NSAlert(error: error)
                alert.informativeText = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
                alert.runModal()
            }
        }

        // Switch to the last imported preset
        if let preset = lastImported {
            audioEngine.activePreset = preset
            syncUIToPreset()
            saveState()
        }
    }

    private func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func saveState() {
        var state = iQualizeState.load()
        state.selectedPresetID = audioEngine.activePreset.id
        state.save()
    }
}
