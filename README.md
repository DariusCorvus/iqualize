# iQualize

System-wide audio equalizer for macOS. A native Swift menu bar app that captures all system audio via Core Audio Taps, applies EQ processing, and plays it back through your output device.

## Features

- Customizable EQ bands with editable dB, Hz, and Q values
- Drag-and-drop band reordering
- Add/remove bands inline with + buttons
- Adjustable max dB cap (±6/12/18/24)
- Low Latency mode (50ms ring buffer)
- Preset management: save, save as, import/export JSON
- Anti-clipping preamp reduction (toggleable)
- Automatic device switching
- Sleep/wake handling
- State persistence across launches (including window state)

## Requirements

- macOS 14.2+ (Core Audio Taps API)
- Screen & System Audio Recording permission

## Install

```bash
bash install.sh          # builds, signs, installs to /Applications
open /Applications/iQualize.app
```

## Architecture

```
System Audio → CATap (muted) → IOProc → Ring Buffer → AVAudioSourceNode → EQ → Output Device
```

iQualize excludes its own process from the tap to prevent feedback loops. The app uses a private aggregate device combining the real output device with the tap stream.
