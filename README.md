# iQualize

> macOS doesn't have a system-wide parametric EQ.
> So I built one in a day.

![iQualize at 04:57](./preview.webp)

Built at 04:57 in Bavaria, listening to [Opera by Ballarak](https://open.spotify.com/track/6EkjiVchNqlYHoc2YNMiaV) on a Teufel Concept E 5.1.
That's the only explanation you need for why this exists.

---

## What it is

A native macOS system-wide parametric EQ with a real-time Pre/Post spectrum analyzer.
No virtual audio drivers. No Electron. No paywall.
Just Swift, CoreAudio, and a CATap doing what they should've always done.

## Why not eqMac

eqMac uses a virtual audio driver.
iQualize uses a CATap — Apple's native system audio tap introduced in macOS 14.
No driver to install. No driver to break. No driver to fight with Bluetooth.
It just works.

## Requirements

- macOS 14.2+ (Core Audio Taps API)
- Screen & System Audio Recording permission

## Install

### Download (recommended)

Grab the latest `.dmg` from [Releases](https://github.com/DariusCorvus/iqualize/releases), open it, and drag iQualize to Applications.

iQualize is unsigned. Apple charges $99/year for a developer certificate. If macOS blocks the app, run:

```bash
xattr -dr com.apple.quarantine /Applications/iQualize.app
```

### Build from source

```bash
bash install.sh          # builds, signs, installs to /Applications
open /Applications/iQualize.app
```

## Features

### Parametric EQ

- Up to 31 bands with editable frequency (20 Hz – 20 kHz), gain, and Q/bandwidth
- 7 filter types per band: Bell (parametric), Low Shelf, High Shelf, Low Pass, High Pass, Band Pass, and Notch
- Accurate biquad frequency response curve using Audio EQ Cookbook formulas, rendered as a translucent backdrop behind EQ sliders
- Per-band ghost fills, anchor dots with dB labels, and split boost/cut composite fill
- Axis labels and detailed frequency/dB grid overlay
- Catmull-Rom spline interpolation connecting slider knob positions (dashed gray line)
- Adjustable max gain range: ±6, ±12, ±18, or ±24 dB
- Dynamic peak limiter (AUPeakLimiter) — prevents digital clipping at 0 dBFS
- Smooth, glitch-free parameter updates — only changed values are written to the audio unit

### Band Management

- Add bands with + buttons on either side of the EQ — new band copies the leftmost or rightmost band
- Delete, reorder via drag-and-drop or right-click context menu (Move Left/Right)
- Minimum 1 band, maximum 31

### Presets

- Built-in presets: Flat, Bass Boost, Vocal Clarity, Loudness, Treble Boost, Podcast, Techno, Deep House, Hard Techno, Minimal, American Rap, German Rap
- Create, rename, overwrite, and delete custom presets
- Built-in presets auto-fork when edited (non-destructive)
- Unsaved changes indicator (asterisk in title)
- Import/export as `.iqpreset` JSON files with batch import and overwrite protection
- Quick switching from the menu bar or EQ window picker

#### Preset Format

Presets are `.iqpreset` files — plain JSON:

```json
{
  "bands": [
    { "bandwidth": 1.0, "filterType": "parametric", "frequency": 80, "gain": 5 },
    { "bandwidth": 1.2, "filterType": "lowShelf", "frequency": 200, "gain": -3 }
  ],
  "id": "CDE9BB8A-12A5-420C-9619-2790E20030D5",
  "isBuiltIn": false,
  "name": "My Preset"
}
```

Each band: `frequency` (Hz, 20–20000), `gain` (dB), `bandwidth` (Q factor — lower is wider, higher is narrower), `filterType` (one of `parametric`, `lowShelf`, `highShelf`, `lowPass`, `highPass`, `bandPass`, `notch` — defaults to `parametric` if omitted).

### Undo/Redo

- Full undo/redo for all EQ modifications (gain, frequency, bandwidth, reorder, add, delete)
- Slider drags coalesced into single undo actions
- Cmd+Z / Cmd+Shift+Z

### Keyboard & Scroll

- Click a band to select it (accent-colored border indicator)
- Arrow Up/Down to adjust gain (±0.5 dB per step)
- Arrow Left/Right to adjust frequency (semitone steps)
- Tab / Shift+Tab to cycle between bands
- Scroll wheel over sliders to adjust gain
- Scroll wheel over frequency/Q inputs to adjust those values
- Rapid adjustments coalesced into single undo entries

### Menu Bar

- Presets submenu with checkmarks and active preset name in parent item
- Bypass EQ toggle (Cmd+B) — pass audio through unprocessed
- Peak Limiter toggle
- Current output device display
- Open EQ window (Cmd+,)

### Spectrum Analyzer

- Dual real-time spectrum analyzer: pre-EQ (raw input) and post-EQ (processed output)
- Independent toggle checkboxes for pre-EQ and post-EQ display
- 2048-point FFT via Accelerate vDSP with Hann windowing and log-frequency binning
- Smooth Catmull-Rom spline rendering with peak hold lines
- Lock-free double-buffered audio-to-UI transfer for glitch-free 60fps updates
- Monochrome white/gray spectrum layers with z-ordered rendering; blue EQ response curve is the only colored element
- Spectrum toggle states persist across app restarts

### System Integration

- Automatic output device switching and reconnection
- Sleep/wake handling — pauses on sleep, resumes on wake
- Window state and all settings persist across launches
- Codesigned for stable TCC permissions across rebuilds
- Built with Swift Package Manager — no Xcode project needed

## Architecture

iQualize uses Core Audio Taps (CATap), introduced in macOS 14.2, to intercept system audio without a virtual audio device. Virtual devices (like BlackHole or eqMac's driver approach) create a secondary audio path — you lose system volume control, break some DRM-protected audio, and add latency. CATap captures the audio stream directly from the HAL, processes it in-process, and sends it to the output device.

```
┌─────────────────────────────────────────────────┐
│  macOS Audio Server                             │
│                                                 │
│  App Audio ──┬── Output Device (muted by tap)   │
│              │                                  │
│              └── CATap ──► iQualize IOProc      │
│                            │                    │
│                            ▼                    │
│                       Ring Buffer               │
│                            │                    │
│                            ▼                    │
│                   AVAudioSourceNode             │
│                            │                    │
│                            ▼                    │
│                    AVAudioUnitEQ                 │
│                    (parametric EQ)               │
│                            │                    │
│                            ▼                    │
│                    Output Device                 │
└─────────────────────────────────────────────────┘
```

The ring buffer decouples the real-time IOProc callback from AVAudioEngine's pull model. Parameter changes are written atomically — no locks in the audio thread, no glitches on slider drags.

## Output Handling

iQualize detects the output device's sample rate and converts internally so the audio plays back correctly regardless of what device you're on. Bluetooth sends stereo (2ch) only — SBC, AAC, and aptX all max out at 2 channels. If your speaker system supports 5.1 (e.g. Teufel Concept E via USB), the hardware handles channel routing and upmixing (Dolby Pro Logic II etc) on its end.

---

I build tools that shouldn't need to exist.

[darius.codes](https://darius.codes)
