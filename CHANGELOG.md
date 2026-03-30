# Changelog

All notable changes to iQualize will be documented in this file.

## [0.15.0] - 2026-03-30

### Changed
- Replace static "Prevent Clipping" with a real dynamic peak limiter using Apple's AUPeakLimiter
- Rename "Prevent Clipping" to "Peak Limiter" in menu bar and EQ window
- Rename `preventClipping` property and JSON key to `peakLimiter`

### Removed
- Static preamp gain reduction (`preampGain` computed property)
- Legacy state migration code (no existing users to migrate)

## [0.13.0] - 2026-03-30

### Added
- Keyboard shortcuts for EQ band adjustments: Arrow Up/Down for gain (±0.5 dB), Arrow Left/Right for frequency (semitone steps)
- Tab/Shift+Tab to cycle selection between bands
- Visual selection indicator with accent-colored border on the active band
- Scroll wheel support: hover over sliders, frequency inputs, or Q inputs to adjust values by scrolling
- Click-to-select on band columns clears text field focus for immediate keyboard control
- Undo coalescing for rapid keyboard and scroll adjustments (500ms timer groups into single undo entry)

## [0.11.0] - 2026-03-30

### Added
- Accurate biquad frequency response curve using Audio EQ Cookbook formulas, showing the true filter response behind the EQ sliders
- Per-band ghost fills showing individual filter contribution shapes
- Anchor dots with drop lines and dB labels at each band's frequency on the composite curve
- Split composite fill (boost regions brighter than cut regions)
- Detailed frequency/dB grid (20Hz–20kHz vertical, 6dB horizontal)
- Axis labels (+12, 0, -12 dB) in the left margin outside the graph area
- American Rap built-in preset (808-heavy sub-bass, mid scoop, vocal presence)
- German Rap built-in preset (warm mid-bass, vocal clarity, balanced brightness)

### Changed
- Spline curve (connecting slider knobs) now rendered as a dashed gray line to distinguish from the biquad response
- install.sh now re-signs the app when only Info.plist changes (fixes launch failures after version bump)

## [0.10.0] - 2026-03-30

### Added
- Per-band filter type selection with 7 filter types: Bell (parametric), Low Shelf, High Shelf, Low Pass, High Pass, Band Pass, and Notch
- Frequency response curve rendered as a backdrop behind EQ sliders
- Per-filter-type curve shapes that visually match each filter's behavior
- Catmull-Rom spline interpolation for pixel-perfect curve-to-handle alignment
- Notch (band stop) filter type for surgical frequency cuts

### Changed
- Response curve is now always visible as a translucent backdrop behind sliders (replaced collapsible standalone panel)
- `isFlat` check now considers filter type (non-parametric bands are not "flat")
- Add-band operations now copy the reference band's filter type

### Fixed
- Curve alignment with slider handles across all band configurations
- Coordinate conversion through flipped/non-flipped view hierarchies
- Frequency response curve now updates when changing a band's filter type
- Guard against division by zero with zero-bandwidth parametric bands
