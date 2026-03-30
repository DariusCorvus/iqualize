import CoreAudio
import AudioToolbox
import AVFAudio
import Foundation
import Observation
import os.log

private let appLog = OSLog(subsystem: "com.iqualize", category: "audio")

// MARK: - Real-time Audio Callbacks (free functions, no actor isolation)
// These run on Core Audio's IO thread. They MUST be free functions — not closures
// defined inside a @MainActor class — because Swift 6 strict concurrency inserts
// runtime isolation checks that crash on non-main threads.

nonisolated(unsafe) private var rtRingBuffer: AudioRingBuffer?
nonisolated(unsafe) private var rtChannelCount: UInt32 = 2

/// Scratch buffer for deinterleaving (allocated once, reused).
nonisolated(unsafe) private var rtScratchBuffer: UnsafeMutablePointer<Float>?
nonisolated(unsafe) private var rtScratchCapacity: Int = 0

/// AVAudioSourceNode render block: pulls interleaved audio from ring buffer,
/// deinterleaves into separate channel buffers for the non-interleaved AVAudioEngine format.
private func renderCallback(
    _: UnsafeMutablePointer<ObjCBool>,
    _: UnsafePointer<AudioTimeStamp>,
    frameCount: UInt32,
    audioBufferList: UnsafeMutablePointer<AudioBufferList>
) -> OSStatus {
    guard let ringBuf = rtRingBuffer else { return noErr }
    let ch = Int(rtChannelCount)
    let frames = Int(frameCount)
    let interleavedCount = frames * ch
    let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)

    if rtScratchCapacity < interleavedCount {
        rtScratchBuffer?.deallocate()
        rtScratchBuffer = .allocate(capacity: interleavedCount)
        rtScratchCapacity = interleavedCount
    }
    guard let scratch = rtScratchBuffer else { return noErr }

    let read = ringBuf.read(scratch, count: interleavedCount)
    if read < interleavedCount {
        scratch.advanced(by: read).initialize(repeating: 0.0, count: interleavedCount - read)
    }

    for i in 0..<bufferList.count {
        guard let outData = bufferList[i].mData?.assumingMemoryBound(to: Float.self) else { continue }
        let channelIndex = i
        for f in 0..<frames {
            outData[f] = scratch[f * ch + channelIndex]
        }
    }
    return noErr
}

// MARK: - AudioEngine

@available(macOS 14.2, *)
@Observable
@MainActor
final class AudioEngine {
    private(set) var isRunning = false
    private(set) var outputDeviceName = "Unknown"
    private(set) var error: String?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var engine: AVAudioEngine?
    private var eq: AVAudioUnitEQ?
    private var limiter: AVAudioUnitEffect?
    private var ringBuffer: AudioRingBuffer?
    private var tapUUID = UUID()

    @ObservationIgnored
    nonisolated(unsafe) private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?
    var onStateChange: (() -> Void)?

    // Spectrum analyzers — one per tap point
    let preEqAnalyzer = SpectrumAnalyzer()
    let postEqAnalyzer = SpectrumAnalyzer()
    private var sourceNode: AVAudioSourceNode?

    var activePreset: EQPresetData = .flat {
        didSet {
            applyBands(from: oldValue)
        }
    }

    var peakLimiter: Bool = true {
        didSet { applyBands() }
    }

    var bypassed: Bool = false {
        didSet { applyBands() }
    }

    var maxGainDB: Float = 12
    private(set) var outputSampleRate: Double = 48000

    init() {
        do {
            let deviceID = try getDefaultOutputDeviceID()
            outputDeviceName = try getDeviceName(deviceID)
        } catch {
            outputDeviceName = "Unknown"
        }
        installDeviceChangeListener()
    }

    deinit {
        if let block = deviceChangeListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address,
                DispatchQueue.main, block
            )
        }
    }

    // MARK: - Start / Stop

    func start() throws {
        guard !isRunning else { return }
        error = nil

        let outputDeviceID = try getDefaultOutputDeviceID()
        let outputUID = try getDeviceUID(outputDeviceID)
        outputDeviceName = try getDeviceName(outputDeviceID)

        // 1. Translate our PID → AudioObjectID so we can exclude ourselves from the tap.
        //    Without this, the muted tap silences iQualize's own AVAudioEngine output.
        var translateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var myPID = ProcessInfo.processInfo.processIdentifier
        var myProcessObjectID = AudioObjectID(kAudioObjectUnknown)
        var processObjectSize = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &translateAddress,
            UInt32(MemoryLayout<pid_t>.size), &myPID,
            &processObjectSize, &myProcessObjectID
        )

        // 2. Create global tap (muted), excluding iQualize's own process
        tapUUID = UUID()
        let excludeProcesses: [AudioObjectID] = myProcessObjectID != kAudioObjectUnknown
            ? [myProcessObjectID] : []
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: excludeProcesses)
        tapDesc.uuid = tapUUID
        tapDesc.muteBehavior = .muted
        tapDesc.name = "iQualize-EQ"

        tapID = AudioObjectID(kAudioObjectUnknown)
        try caCheck(
            AudioHardwareCreateProcessTap(tapDesc, &tapID),
            "Failed to create process tap"
        )

        // 3. Read tap format
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try caCheck(
            AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &tapFormat),
            "Failed to get tap format"
        )
        let tapSampleRate = tapFormat.mSampleRate
        let channels = tapFormat.mChannelsPerFrame

        // Read the output device's native sample rate for comparison
        var nominalRateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceSampleRate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(outputDeviceID, &nominalRateAddress, 0, nil, &rateSize, &deviceSampleRate)

        // Use the output device's native sample rate for AVAudioEngine.
        // The tap may capture at a different rate (e.g., 48kHz tap vs 44.1kHz Bluetooth).
        // The aggregate device handles resampling between the tap and the IOProc.
        let sampleRate = deviceSampleRate > 0 ? deviceSampleRate : tapSampleRate
        self.outputSampleRate = sampleRate

        os_log(.default, log: appLog,
               "tapRate: %{public}.0f  deviceRate: %{public}.0f  using: %{public}.0f  channels: %{public}u  device: %{public}@",
               tapSampleRate, deviceSampleRate, sampleRate, channels, outputDeviceName as NSString)

        // 4. Create aggregate device with tap and output device in the creation dictionary.
        //    The tap list MUST be included at creation time — adding it later via
        //    kAudioAggregateDevicePropertyTapList delivers zero-filled buffers.
        let aggregateUID = UUID().uuidString
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "iQualize-Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                ]
            ],
        ]

        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        try caCheck(
            AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateDeviceID),
            "Failed to create aggregate device"
        )

        // Wait for device alive
        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for _ in 1...30 {
            var isAlive: UInt32 = 0
            var aliveSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(aggregateDeviceID, &aliveAddress, 0, nil, &aliveSize, &isAlive)
            if isAlive != 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        // 5. Set up ring buffer + AVAudioEngine with EQ
        let bufferSeconds = 0.5
        let ringBuf = AudioRingBuffer(capacityFrames: Int(sampleRate * bufferSeconds), channels: Int(channels))
        self.ringBuffer = ringBuf
        rtRingBuffer = ringBuf
        rtChannelCount = channels

        let avEngine = AVAudioEngine()

        // Explicitly set output to the real hardware device so iQualize's playback
        // goes directly to hardware, matching the gain staging of the original audio.
        var outputID = outputDeviceID
        let outputAU = avEngine.outputNode.audioUnit!
        AudioUnitSetProperty(
            outputAU,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &outputID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                   channels: AVAudioChannelCount(channels))!

        let sourceNode = AVAudioSourceNode(format: format, renderBlock: renderCallback)
        self.sourceNode = sourceNode

        let eqNode = AVAudioUnitEQ(numberOfBands: EQPresetData.maxBandCount)
        for (i, eqBand) in eqNode.bands.enumerated() {
            if i < activePreset.bands.count {
                let band = activePreset.bands[i]
                eqBand.filterType = band.filterType.avType
                eqBand.frequency = band.frequency
                eqBand.bandwidth = band.bandwidth
                eqBand.gain = band.gain
                eqBand.bypass = false
            } else {
                eqBand.bypass = true
            }
        }
        eqNode.globalGain = 0
        eqNode.bypass = bypassed || activePreset.isFlat
        self.eq = eqNode

        // Peak limiter: dynamic limiting at 0 dBFS (replaces static preamp hack)
        let limiterDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let limiterNode = AVAudioUnitEffect(audioComponentDescription: limiterDesc)
        let au = limiterNode.audioUnit
        AudioUnitSetParameter(au, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.007, 0)
        AudioUnitSetParameter(au, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.024, 0)
        AudioUnitSetParameter(au, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0.0, 0)
        limiterNode.bypass = !peakLimiter || bypassed
        self.limiter = limiterNode

        avEngine.attach(sourceNode)
        avEngine.attach(eqNode)
        avEngine.attach(limiterNode)
        avEngine.connect(sourceNode, to: eqNode, format: format)
        avEngine.connect(eqNode, to: limiterNode, format: format)
        avEngine.connect(limiterNode, to: avEngine.outputNode, format: format)

        try avEngine.start()
        self.engine = avEngine

        // 5b. Install spectrum analyzer taps (non-destructive, analysis only)
        // Closures must be @Sendable — they run on the audio render thread, not main.
        // Capture only Sendable values (SpectrumAnalyzer is @unchecked Sendable).
        let capturedSampleRate = sampleRate
        let preAnalyzer: SpectrumAnalyzer = self.preEqAnalyzer
        sourceNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable buffer, _ in
            preAnalyzer.process(buffer, sampleRate: capturedSampleRate)
        }
        let postAnalyzer: SpectrumAnalyzer = self.postEqAnalyzer
        eqNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable buffer, _ in
            postAnalyzer.process(buffer, sampleRate: capturedSampleRate)
        }

        // 6. Install IOProc on aggregate device — captures tap audio → ring buffer
        let ioBlock: AudioDeviceIOBlock = { _, inInputData, _, outOutputData, _ in
            guard let ringBuf = rtRingBuffer else { return }

            let inBufList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            for i in 0..<inBufList.count {
                guard let data = inBufList[i].mData else { continue }
                let sampleCount = Int(inBufList[i].mDataByteSize) / MemoryLayout<Float>.size
                ringBuf.write(data.assumingMemoryBound(to: Float.self), count: sampleCount)
            }

            // Zero the output buffers (silence — playback goes through AVAudioEngine)
            let outBufList = UnsafeMutableAudioBufferListPointer(outOutputData)
            for i in 0..<outBufList.count {
                if let data = outBufList[i].mData {
                    memset(data, 0, Int(outBufList[i].mDataByteSize))
                }
            }
        }
        try caCheck(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, nil, ioBlock),
            "Failed to create IOProc"
        )

        try caCheck(
            AudioDeviceStart(aggregateDeviceID, procID),
            "Failed to start aggregate device"
        )

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        rtRingBuffer = nil
        ringBuffer = nil

        // Remove spectrum taps before stopping engine
        sourceNode?.removeTap(onBus: 0)
        eq?.removeTap(onBus: 0)
        sourceNode = nil

        AudioDeviceStop(aggregateDeviceID, procID)
        engine?.stop()
        engine = nil
        eq = nil
        limiter = nil

        if let procID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            self.procID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: - EQ Control

    func setEnabled(_ enabled: Bool) {
        if enabled {
            do {
                try start()
            } catch {
                self.error = error.localizedDescription
            }
        } else {
            stop()
        }
    }

    private func applyBands(from old: EQPresetData? = nil) {
        guard let eq else { return }
        let newCount = activePreset.bands.count
        let oldCount = old?.bands.count ?? 0

        for (i, band) in activePreset.bands.enumerated() {
            let eqBand = eq.bands[i]
            if i >= oldCount {
                // New band — configure fully
                eqBand.filterType = band.filterType.avType
                eqBand.frequency = band.frequency
                eqBand.bandwidth = band.bandwidth
                eqBand.gain = band.gain
                eqBand.bypass = false
            } else if let oldBand = old?.bands[i] {
                // Existing band — only update changed params
                if band.filterType != oldBand.filterType { eqBand.filterType = band.filterType.avType }
                if band.frequency != oldBand.frequency { eqBand.frequency = band.frequency }
                if band.gain != oldBand.gain { eqBand.gain = band.gain }
                if band.bandwidth != oldBand.bandwidth { eqBand.bandwidth = band.bandwidth }
            } else {
                // No old data — write everything
                eqBand.filterType = band.filterType.avType
                eqBand.frequency = band.frequency
                eqBand.gain = band.gain
                eqBand.bandwidth = band.bandwidth
            }
        }

        // Bypass bands that are no longer active
        if newCount < oldCount {
            for i in newCount..<oldCount {
                eq.bands[i].bypass = true
            }
        }

        eq.globalGain = 0
        limiter?.bypass = !peakLimiter || bypassed
        eq.bypass = bypassed || activePreset.isFlat
    }

    // MARK: - Device Change Handling

    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handleDeviceChange()
                }
            }
        }
        deviceChangeListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address,
            DispatchQueue.main, block
        )
    }

    private var isRestarting = false

    private func handleDeviceChange() {
        guard !isRestarting else { return }

        if let deviceID = try? getDefaultOutputDeviceID(),
           let name = try? getDeviceName(deviceID) {
            outputDeviceName = name
        }

        if isRunning {
            isRestarting = true
            stop()
            do {
                try start()
            } catch {
                self.error = error.localizedDescription
            }
            isRestarting = false
        }

        onStateChange?()
    }
}
