# iQualize

System-wide audio equalizer for macOS. A native Swift menu bar app that captures all system audio via Core Audio Taps, applies parametric EQ processing, and plays it back through your output device — no kernel extensions, no virtual audio drivers.

```
System Audio → CATap (muted) → IOProc → Ring Buffer → AVAudioSourceNode → EQ → Output Device
```

## Requirements

- macOS 14.2+ (Core Audio Taps API)
- Screen & System Audio Recording permission

## Install

```bash
bash install.sh          # builds, signs, installs to /Applications
open /Applications/iQualize.app
```

## Features

### Equalizer
- Up to 31 parametric EQ bands with editable frequency (20 Hz–20 kHz), gain, and Q/bandwidth
- Adjustable max gain range: ±6, ±12, ±18, or ±24 dB
- Anti-clipping preamp that automatically reduces gain to prevent digital clipping
- Low Latency mode (50ms buffer) for real-time monitoring
- Smooth, glitch-free parameter updates — only changed values are written to the audio unit

### Band Management
- Add bands with + buttons on either side of the EQ
- Smart frequency suggestions — new bands fill the largest spectral gap
- Delete, reorder via drag-and-drop or right-click context menu (Move Left/Right)
- Minimum 1 band, maximum 31

### Presets
- Built-in presets: Flat, Bass Boost, Vocal Clarity
- Create, rename, overwrite, and delete custom presets
- Built-in presets auto-fork when edited
- Unsaved changes indicator (asterisk in title)
- Import/export as `.iqpreset` JSON files with batch import and overwrite protection
- Quick switching from the menu bar or EQ window picker

### Undo/Redo
- Full undo/redo for all EQ modifications (gain, frequency, bandwidth, reorder, add, delete)
- Slider drags coalesced into single undo actions
- Cmd+Z / Cmd+Shift+Z

### Menu Bar
- Quick preset selection with checkmarks
- Prevent Clipping and Low Latency toggles
- Current output device display
- Open EQ window (Cmd+,)

### System Integration
- Automatic output device switching and reconnection
- Sleep/wake handling — pauses on sleep, resumes on wake
- Window state and all settings persist across launches
- Codesigned for stable TCC permissions across rebuilds
- Built with Swift Package Manager — no Xcode project needed

## Roadmap

- [ ] Visual frequency response curve
- [ ] Per-app audio routing (EQ only specific apps)
- [ ] More built-in presets (Loudness, Treble Boost, Podcast, etc.)
- [ ] Preset sharing / community presets
- [ ] Audio spectrum analyzer / visualizer
- [ ] Keyboard shortcuts for band adjustments
- [ ] Sparkle auto-updates
- [ ] Menu bar waveform or level meter
