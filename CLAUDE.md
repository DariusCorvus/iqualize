# iQualize

Cross-platform system-wide audio equalizer.

## Repository Structure

```
macos/    — macOS version (Swift/AppKit/CoreAudio)
linux/    — Linux version (Rust/Tauri v2/SvelteKit/PipeWire)
```

## Version Bumping

### macOS
Version lives in `macos/Sources/iQualize/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`).

### Linux
Version lives in `linux/src-tauri/Cargo.toml` and `linux/src-tauri/tauri.conf.json`.

**When to bump:**
- **Patch** (0.3.0 → 0.3.1): bug fixes only
- **Minor** (0.3.0 → 0.4.0): new features or UI changes
- **Major** (0.3.0 → 1.0.0): breaking changes or public release

**Rules:**
- Bump the version in the PR that introduces the change, not in a separate PR
- Multiple bug fixes in one PR = one patch bump
- Multiple features in one PR = one minor bump
- You MUST check and bump the version on every PR — do not wait for the user to remind you

## Task Tracking

Use GitHub Issues for backlog and todos. At the start of each session, check `gh issue list` for open work.

- **bug**: something broken
- **feature**: new functionality
- **polish**: UI/UX improvements

When closing a task via PR, use "Fixes #N" in the PR body to auto-close the issue.

## macOS Build & Install

```bash
cd macos
bash install.sh          # builds, signs with Apple Development cert, installs to /Applications
open /Applications/iQualize.app
```

## macOS Dev Workflow

- Build with `swift build` (SPM, no Xcode project)
- After code changes: `pkill -x iQualize; bash install.sh && open /Applications/iQualize.app`
- Binary is codesigned with "Apple Development" cert to preserve TCC permissions across rebuilds
- install.sh skips binary copy if unchanged (preserves cdhash)

### Launch verification (REQUIRED — macOS)

After every build+install, you MUST verify the app actually launches:

```bash
cd macos
pkill -x iQualize; bash install.sh && open /Applications/iQualize.app
sleep 2
pgrep -x iQualize > /dev/null && echo "OK: app running" || echo "FAIL: app did not start"
```

**A task is not done until the app launches successfully.** Never skip this step.

## Linux Build & Dev

```bash
cd linux
nix develop              # enter NixOS dev shell (provides all deps)
pnpm install             # install SvelteKit dependencies
cargo tauri dev          # start dev server (hot reload frontend + Rust backend)
```

### Production build (Linux)

```bash
cd linux
cargo tauri build        # produces AppImage/deb in src-tauri/target/release/bundle/
# or via Nix:
nix build                # reproducible build
```

## macOS Architecture

- `macos/Sources/iQualize/iQualizeApp.swift` — app entry, NSApplicationDelegate
- `macos/Sources/iQualize/MenuBarController.swift` — menu bar icon + dropdown
- `macos/Sources/iQualize/EQWindowController.swift` — standalone EQ window (sliders, inputs, presets, spectrum visualization)
- `macos/Sources/iQualize/SettingsWindowController.swift` — global Settings window (Audio, Display, General sections)
- `macos/Sources/iQualize/AudioEngine.swift` — system audio capture + AVAudioEngine EQ processing
- `macos/Sources/iQualize/EQPreset.swift` — state persistence + preset data model
- `macos/Sources/iQualize/EQModels.swift` — EQBand, EQPresetData, PresetStore
- `macos/Sources/iQualize/BiquadResponse.swift` — biquad filter frequency response calculation (Audio EQ Cookbook)
- `macos/Sources/iQualize/SpectrumAnalyzer.swift` — real-time FFT spectrum analysis via Accelerate vDSP
- `macos/Sources/iQualize/SpectrumData.swift` — lock-free double-buffered audio-to-UI data transfer

## Linux Architecture

- `linux/src-tauri/src/audio/pipewire_filter.rs` — PipeWire filter node for system audio capture + EQ routing
- `linux/src-tauri/src/dsp/biquad.rs` — biquad filter coefficients + real-time filter chains (ported from Swift)
- `linux/src-tauri/src/dsp/fft.rs` — FFT spectrum analyzer using rustfft (ported from vDSP)
- `linux/src-tauri/src/dsp/ring_buffer.rs` — lock-free SPSC ring buffer
- `linux/src-tauri/src/dsp/spectrum_data.rs` — double-buffered audio→UI data transfer
- `linux/src-tauri/src/dsp/limiter.rs` — peak limiter (envelope follower)
- `linux/src-tauri/src/state/persistence.rs` — JSON state persistence (~/.config/iqualize/)
- `linux/src-tauri/src/state/presets.rs` — 15 built-in presets (matching macOS)
- `linux/src-tauri/src/commands.rs` — Tauri command handlers
- `linux/src-tauri/src/tray.rs` — system tray menu
- `linux/src/lib/components/` — SvelteKit UI components
- `linux/src/lib/utils/biquad-response.ts` — client-side frequency response calculation
- `linux/flake.nix` — NixOS dev shell + package build
