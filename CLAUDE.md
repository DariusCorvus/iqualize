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

## Architecture

- `Sources/iQualize/iQualizeApp.swift` — app entry, NSApplicationDelegate
- `Sources/iQualize/MenuBarController.swift` — menu bar icon + dropdown
- `Sources/iQualize/EQWindowController.swift` — standalone EQ window (sliders, inputs, presets)
- `Sources/iQualize/AudioEngine.swift` — system audio capture + AVAudioEngine EQ processing
- `Sources/iQualize/EQPreset.swift` — state persistence + preset data model
- `Sources/iQualize/EQModels.swift` — EQBand, EQPresetData, PresetStore
