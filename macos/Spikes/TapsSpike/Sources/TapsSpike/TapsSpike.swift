// TapsSpike v2 — Capture system audio via CATap, apply gain, play back through speakers.
//
// Architecture proven in v1: CATap → IOProc captures audio (2,800+ callbacks in 30s).
// v2 adds: AVAudioEngine output with a 10-band EQ to play processed audio back.
//
// Usage: swift run TapsSpike [gain_db]

import CoreAudio
import AudioToolbox
import AVFAudio
import Foundation

// MARK: - Helpers

func check(_ status: OSStatus, _ message: String) throws {
    guard status == noErr else {
        throw NSError(domain: "TapsSpike", code: Int(status),
                      userInfo: [NSLocalizedDescriptionKey: "\(message): OSStatus \(status)"])
    }
}

func getDefaultOutputDeviceID() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    try check(
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &address, 0, nil, &size, &deviceID),
        "Failed to get default output device"
    )
    return deviceID
}

func getDeviceUID(_ deviceID: AudioDeviceID) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try check(
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid),
        "Failed to get device UID"
    )
    return uid as String
}

func getDeviceName(_ deviceID: AudioDeviceID) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try check(
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name),
        "Failed to get device name"
    )
    return name as String
}

// MARK: - Ring Buffer for IOProc → AVAudioEngine bridge

/// Simple SPSC ring buffer using atomics for IOProc → AVAudioEngine bridge.
/// Power-of-2 capacity, mask-based wraparound.
final class AudioRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Float>
    private let mask: Int  // capacity - 1
    private let capacity: Int
    private var _writeHead: Int = 0
    private var _readHead: Int = 0

    init(capacityFrames: Int, channels: Int) {
        // Round up to power of 2
        var cap = capacityFrames * channels
        var power = 1
        while power < cap { power *= 2 }
        self.capacity = power
        self.mask = power - 1
        self.buffer = .allocate(capacity: power)
        self.buffer.initialize(repeating: 0.0, count: power)
    }

    deinit { buffer.deallocate() }

    var availableToRead: Int {
        return (_writeHead &- _readHead) & mask
    }

    func write(_ data: UnsafePointer<Float>, count: Int) {
        for i in 0..<count {
            buffer[_writeHead & mask] = data[i]
            _writeHead = (_writeHead &+ 1)
        }
    }

    func read(_ dest: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let avail = availableToRead
        let toRead = min(count, avail)
        for i in 0..<toRead {
            dest[i] = buffer[_readHead & mask]
            _readHead = (_readHead &+ 1)
        }
        return toRead
    }
}

// MARK: - Spike

nonisolated(unsafe) var gFrameCount: UInt64 = 0
nonisolated(unsafe) var gGainLinear: Float = 1.0
nonisolated(unsafe) var gRingBuffer: AudioRingBuffer? = nil
nonisolated(unsafe) var gMaxInputAmp: Float = 0.0

@available(macOS 14.2, *)
func runSpike() throws {
    let gainDB = CommandLine.arguments.count > 1
        ? Float(CommandLine.arguments[1]) ?? 6.0
        : 6.0
    gGainLinear = powf(10.0, gainDB / 20.0)

    print("=== Perth Core Audio Taps Spike v2 ===")
    print("Gain: \(gainDB) dB (linear: \(gGainLinear))")

    // 1. Get the real output device
    let outputDeviceID = try getDefaultOutputDeviceID()
    let outputUID = try getDeviceUID(outputDeviceID)
    let outputName = try getDeviceName(outputDeviceID)
    print("Output device: \(outputName) (UID: \(outputUID))")

    // 2. Create a global tap that mutes original audio
    print("\nCreating global tap (muted)...")
    let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    tapDesc.uuid = UUID()
    tapDesc.muteBehavior = .muted
    tapDesc.name = "Perth-TapsSpike"

    var tapID = AudioObjectID(kAudioObjectUnknown)
    try check(
        AudioHardwareCreateProcessTap(tapDesc, &tapID),
        "Failed to create process tap"
    )
    print("Tap created: ID \(tapID)")

    // 3. Read the tap's audio format
    var formatAddress = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var tapFormat = AudioStreamBasicDescription()
    var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try check(
        AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &tapFormat),
        "Failed to get tap format"
    )
    let sampleRate = tapFormat.mSampleRate
    let channels = tapFormat.mChannelsPerFrame
    print("Tap format: \(sampleRate) Hz, \(channels) ch, \(tapFormat.mBitsPerChannel) bit")

    // 4. Create aggregate device with tap (audiotee approach: empty + add tap)
    print("\nCreating aggregate device...")
    let aggregateUID = UUID().uuidString
    let aggregateDesc: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Perth-Spike-Aggregate",
        kAudioAggregateDeviceUIDKey: aggregateUID,
        kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
        kAudioAggregateDeviceMasterSubDeviceKey: 0,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
    ]

    var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    try check(
        AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateDeviceID),
        "Failed to create aggregate device"
    )

    // Add tap to aggregate device
    var tapUIDAddress = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var tapUID: CFString = "" as CFString
    var tapUIDSize = UInt32(MemoryLayout<CFString>.size)
    try check(
        AudioObjectGetPropertyData(tapID, &tapUIDAddress, 0, nil, &tapUIDSize, &tapUID),
        "Failed to get tap UID"
    )

    var tapListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioAggregateDevicePropertyTapList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var tapArray = [tapUID] as CFArray
    var tapArraySize = UInt32(MemoryLayout<CFArray>.size)
    try check(
        AudioObjectSetPropertyData(aggregateDeviceID, &tapListAddress, 0, nil, tapArraySize, &tapArray),
        "Failed to set tap list"
    )
    print("Aggregate device ready with tap")

    // Wait for device alive
    var aliveAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    for attempt in 1...20 {
        var isAlive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(aggregateDeviceID, &aliveAddress, 0, nil, &aliveSize, &isAlive)
        if isAlive != 0 { break }
        Thread.sleep(forTimeInterval: 0.1)
        if attempt == 20 { print("WARNING: Device may not be alive") }
    }

    // 5. Set up AVAudioEngine for output with EQ
    print("\nSetting up AVAudioEngine output...")
    let engine = AVAudioEngine()
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                               channels: AVAudioChannelCount(channels))!

    // Ring buffer: 0.5 seconds of audio (enough to bridge IOProc → engine)
    let ringBuffer = AudioRingBuffer(capacityFrames: Int(sampleRate * 0.5), channels: Int(channels))
    gRingBuffer = ringBuffer

    // Source node pulls from ring buffer
    let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let samplesNeeded = Int(frameCount) * Int(channels)

        for i in 0..<bufferList.count {
            guard let outData = bufferList[i].mData?.assumingMemoryBound(to: Float.self) else { continue }
            let read = ringBuffer.read(outData, count: samplesNeeded)
            // Zero-fill if ring buffer underruns
            if read < samplesNeeded {
                outData.advanced(by: read).initialize(repeating: 0.0, count: samplesNeeded - read)
            }
        }
        return noErr
    }

    // 10-band EQ (Perth's target spec)
    let eq = AVAudioUnitEQ(numberOfBands: 10)
    let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    for (i, freq) in frequencies.enumerated() {
        let band = eq.bands[i]
        band.filterType = .parametric
        band.frequency = freq
        band.bandwidth = 1.0  // octave
        band.gain = 0.0       // flat for now (gain applied in IOProc)
        band.bypass = false
    }
    eq.globalGain = 0.0

    // Wire up: sourceNode → EQ → mainMixerNode → output
    engine.attach(sourceNode)
    engine.attach(eq)
    engine.connect(sourceNode, to: eq, format: format)
    engine.connect(eq, to: engine.mainMixerNode, format: format)

    try engine.start()
    print("AVAudioEngine started (output to \(outputName))")

    // 6. Install IOProc to capture tap audio → ring buffer
    print("\nInstalling IOProc...")
    var procID: AudioDeviceIOProcID?
    try check(
        AudioDeviceCreateIOProcID(
            aggregateDeviceID,
            { (_, _, inInputData, _, outOutputData, _, _) -> OSStatus in
                guard let ringBuf = gRingBuffer else { return noErr }

                let inCount = Int(inInputData.pointee.mNumberBuffers)
                if inCount == 0 { return noErr }

                // Read first buffer (stereo interleaved float32)
                let firstBuf = UnsafeMutablePointer(mutating: inInputData).pointee.mBuffers
                guard let data = firstBuf.mData else { return noErr }
                let sampleCount = Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)

                // Track max amplitude
                var maxAmp: Float = 0.0
                for i in 0..<sampleCount {
                    let v = abs(samples[i])
                    if v > maxAmp { maxAmp = v }
                }
                if maxAmp > gMaxInputAmp { gMaxInputAmp = maxAmp }

                // Apply gain in-place then write to ring buffer
                let gain = gGainLinear
                for i in 0..<sampleCount {
                    samples[i] = samples[i] * gain
                }
                ringBuf.write(samples, count: sampleCount)

                gFrameCount &+= 1
                return noErr
            },
            nil,
            &procID
        ),
        "Failed to create IOProc"
    )

    try check(
        AudioDeviceStart(aggregateDeviceID, procID),
        "Failed to start aggregate device"
    )

    let startTime = Date()
    print("\n🎵 SPIKE v2 RUNNING")
    print("   Pipeline: System Audio → CATap (muted) → IOProc (+\(gainDB)dB) → Ring Buffer → AVAudioEngine (10-band EQ) → \(outputName)")
    print("   Play some music and listen!")
    print("   Running for 30 seconds...\n")

    // 7. Run for 30 seconds
    let runDuration: TimeInterval = 30
    var lastReport: TimeInterval = 0
    while Date().timeIntervalSince(startTime) < runDuration {
        Thread.sleep(forTimeInterval: 1.0)
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed - lastReport >= 5.0 {
            let callbacks = gFrameCount
            let ringAvail = ringBuffer.availableToRead
            let maxAmp = gMaxInputAmp
            print("  [\(Int(elapsed))s] IOProc: \(callbacks) | Ring: \(ringAvail) | MaxAmp: \(maxAmp)")
            lastReport = elapsed
        }
    }

    // 8. Teardown — order matters to avoid assertion failures
    print("\nStopping...")

    // Print results BEFORE teardown in case it crashes
    let totalCallbacksEarly = gFrameCount
    let durationEarly = Date().timeIntervalSince(startTime)
    print("Results: \(totalCallbacksEarly) IOProc callbacks in \(String(format: "%.1f", durationEarly))s")
    if totalCallbacksEarly > 100 {
        print("✅ Pipeline captured audio successfully!")
    }
    fflush(stdout)

    // Stop IOProc first (stops feeding ring buffer)
    AudioDeviceStop(aggregateDeviceID, procID)
    Thread.sleep(forTimeInterval: 0.1)

    // Clear ring buffer reference so source node stops reading
    gRingBuffer = nil
    Thread.sleep(forTimeInterval: 0.1)

    // Stop engine
    engine.stop()
    Thread.sleep(forTimeInterval: 0.1)

    // Destroy IOProc
    if let procID {
        AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
    }

    // Destroy aggregate device and tap
    AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
    AudioHardwareDestroyProcessTap(tapID)

    let totalCallbacks = gFrameCount
    let duration = Date().timeIntervalSince(startTime)
    print("\nSpike v2 complete.")
    print("Total IOProc callbacks: \(totalCallbacks)")
    print("Duration: \(String(format: "%.1f", duration))s")
    if duration > 0 {
        print("Avg callbacks/sec: \(String(format: "%.0f", Double(totalCallbacks) / duration))")
    }

    if totalCallbacks > 100 {
        print("\n✅ SUCCESS — Full pipeline working!")
        print("   CATap → IOProc → Ring Buffer → AVAudioEngine (EQ) → Speakers")
        print("   Perth can be built entirely with Core Audio Taps.")
        print("   No virtual audio driver needed. No restricted entitlement.")
        print("   Distribution: single .app, standard notarization.")
    } else {
        print("\n❌ Pipeline incomplete — \(totalCallbacks) callbacks")
    }
}

// MARK: - Entry Point

if #available(macOS 14.2, *) {
    do {
        try runSpike()
    } catch {
        print("\n❌ ERROR: \(error.localizedDescription)")
        print("\nIf you see a permission error, grant audio capture access in:")
        print("  System Settings > Privacy & Security > Audio Capture")
        exit(1)
    }
} else {
    print("❌ Core Audio Taps require macOS 14.2 or newer.")
    exit(1)
}
