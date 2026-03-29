# Changelog

All notable changes to iQualize will be documented in this file.

## [0.11.0] - 2026-03-30

### Added
- American Rap built-in preset (808-heavy sub-bass, mid scoop, vocal presence)
- German Rap built-in preset (warm mid-bass, vocal clarity, balanced brightness)

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
