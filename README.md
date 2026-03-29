# Perth

System-wide audio equalizer for macOS. A native Swift menu bar app that captures all system audio via Core Audio Taps, applies EQ processing, and plays it back through your output device.

## Features

- 10-band graphic EQ (32Hz–16kHz)
- Presets: Flat, Bass Boost, Vocal Clarity
- Anti-clipping preamp reduction (toggleable)
- Automatic device switching
- Sleep/wake handling
- State persistence across launches

## Requirements

- macOS 14.2+ (Core Audio Taps API)
- Screen & System Audio Recording permission

## Building

```bash
swift build
.build/arm64-apple-macosx/debug/Perth
```

## Architecture

```
System Audio → CATap (muted) → IOProc → Ring Buffer → AVAudioSourceNode → EQ → Output Device
```

Perth excludes its own process from the tap to prevent feedback loops. The app uses a private aggregate device combining the real output device with the tap stream.
