import Foundation

/// Lock-free double-buffered magnitude data for audio→UI transfer.
/// Writer (audio thread) fills the inactive buffer and flips the index.
/// Reader (UI thread) reads from the currently active buffer.
///
/// ARM64 guarantees atomic aligned 32-bit loads/stores, so the index
/// flip is naturally atomic without explicit barriers. Worst case:
/// reader sees one stale frame — imperceptible at 60fps.
final class SpectrumData: @unchecked Sendable {
    static let binCount = 128

    private let buffers: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>)
    private let count: Int  // binCount * 2 (magnitudes + peaks)
    private var activeIndex: Int32 = 0  // 0 or 1

    init() {
        count = Self.binCount * 2
        buffers.0 = .allocate(capacity: count)
        buffers.0.initialize(repeating: -90.0, count: count)
        buffers.1 = .allocate(capacity: count)
        buffers.1.initialize(repeating: -90.0, count: count)
    }

    deinit {
        buffers.0.deallocate()
        buffers.1.deallocate()
    }

    private func buffer(at index: Int32) -> UnsafeMutablePointer<Float> {
        index == 0 ? buffers.0 : buffers.1
    }

    /// Called from audio thread.
    func write(_ magnitudes: UnsafePointer<Float>, peaks: UnsafePointer<Float>) {
        let writeIdx = 1 - activeIndex
        let dest = buffer(at: writeIdx)
        dest.update(from: magnitudes, count: Self.binCount)
        dest.advanced(by: Self.binCount).update(from: peaks, count: Self.binCount)
        activeIndex = writeIdx  // flip — atomic on ARM64
    }

    /// Called from UI thread. Copies current magnitudes and peaks into caller-provided buffers.
    func read(_ magnitudes: UnsafeMutablePointer<Float>, peaks: UnsafeMutablePointer<Float>) {
        let src = buffer(at: activeIndex)
        magnitudes.update(from: src, count: Self.binCount)
        peaks.update(from: src.advanced(by: Self.binCount), count: Self.binCount)
    }
}
