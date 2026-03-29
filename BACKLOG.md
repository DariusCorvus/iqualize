# Perth Backlog

## Medium Priority

### Per-app EQ profiles
Sketch architecture for per-app routing before v1 ships to validate forward-compatibility.

### Custom EQ sliders
v0.2 — separate window with 10 vertical sliders, frequency labels, dB readout, "modified preset" indicator.

### Accessibility
Keyboard navigation, VoiceOver labels, contrast for icon states.

### Low-latency mode
Smaller ring buffer option for users who prefer lower latency over jitter tolerance.

---

## Resolved

### Volume insertion loss with EQ active
**Status:** Fixed
**Fix:** AVAudioEngine was using the tap's sample rate (e.g., 48kHz) instead of the output device's native rate (e.g., 44.1kHz for Bluetooth). The resulting implicit resampling caused volume loss and crackling on devices with mismatched rates. Fixed by reading the output device's `kAudioDevicePropertyNominalSampleRate` and using it for AVAudioEngine's format. The aggregate device handles tap→device resampling natively.
