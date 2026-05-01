# iQualize

macOS menu bar audio equalizer using system audio capture + AVAudioEngine.

## Version Bumping

Version lives in `Sources/iQualize/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`).

**When to bump:**
- **Patch** (0.3.0 → 0.3.1): bug fixes only
- **Minor** (0.3.0 → 0.4.0): new features or UI changes
- **Major** (0.3.0 → 1.0.0): breaking changes or public release

**Rules:**
- Bump the version in the PR that introduces the change, not in a separate PR
- Multiple bug fixes in one PR = one patch bump
- Multiple features in one PR = one minor bump
- Always update both `CFBundleShortVersionString` (e.g. `0.4.0`) and `CFBundleVersion` (e.g. `0.4`)
- You MUST check and bump the version on every PR — do not wait for the user to remind you

## Task Tracking

Use GitHub Issues for backlog and todos. At the start of each session, check `gh issue list` for open work.

- **bug**: something broken
- **feature**: new functionality
- **polish**: UI/UX improvements

When closing a task via PR, use "Fixes #N" in the PR body to auto-close the issue.

## Build & Install

```bash
bash install.sh          # builds, signs with Apple Development cert, installs to /Applications
open /Applications/iQualize.app
```

## Dev Workflow

- Build with `swift build` (SPM, no Xcode project)
- After code changes: `pkill -x iQualize; bash install.sh && open /Applications/iQualize.app`
- Binary is codesigned with "Apple Development" cert to preserve TCC permissions across rebuilds
- install.sh skips binary copy if unchanged (preserves cdhash)

### Launch verification (REQUIRED)

After every build+install, you MUST verify the app actually launches:

```bash
pkill -x iQualize; bash install.sh && open /Applications/iQualize.app
sleep 2
pgrep -x iQualize > /dev/null && echo "OK: app running" || echo "FAIL: app did not start"
```

If the app fails to launch ("can't be opened" error), debug and fix before proceeding. Common causes:
- **TCC/cdhash mismatch**: the codesign identity changed or install.sh didn't re-sign properly
- **Launchd spawn failure**: macOS sometimes needs a few seconds after killing the old process — add `sleep 1` before `open`
- **Crash on startup**: run the binary directly to see the error: `/Applications/iQualize.app/Contents/MacOS/iQualize`

**A task is not done until the app launches successfully.** Never skip this step.

## Architecture

- `Sources/iQualize/iQualizeApp.swift` — app entry, NSApplicationDelegate
- `Sources/iQualize/MenuBarController.swift` — menu bar icon + dropdown
- `Sources/iQualize/EQWindowController.swift` — standalone EQ window (sliders, inputs, presets, spectrum visualization)
- `Sources/iQualize/SettingsWindowController.swift` — global Settings window (Audio, Display, General sections)
- `Sources/iQualize/AudioEngine.swift` — system audio capture + AVAudioEngine EQ processing
- `Sources/iQualize/EQPreset.swift` — state persistence + preset data model
- `Sources/iQualize/EQModels.swift` — EQBand, EQPresetData, PresetStore
- `Sources/iQualize/BiquadResponse.swift` — biquad filter frequency response calculation (Audio EQ Cookbook)
- `Sources/iQualize/SpectrumAnalyzer.swift` — real-time FFT spectrum analysis via Accelerate vDSP
- `Sources/iQualize/SpectrumData.swift` — lock-free double-buffered audio-to-UI data transfer
- `Sources/iQualize/ColorHex.swift` — NSColor ↔ #RRGGBB sRGB hex helpers for persisting user-picked spectrum colors
- `Sources/iQualize/HelpRenderer.swift` — extracts the README's Features section and renders it as HTML via swift-markdown
- `Sources/iQualize/HelpWindowController.swift` — WKWebView-based Help window; intercepts link clicks to open them in the default browser
