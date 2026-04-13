/// Lock-free SPSC ring buffer for bridging IOProc (producer) to AVAudioEngine (consumer).
/// Power-of-2 capacity, wrapping integer arithmetic for correctness.
final class AudioRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let mask: Int
    private var _writeHead: UInt64 = 0
    private var _readHead: UInt64 = 0

    init(capacityFrames: Int, channels: Int) {
        let cap = capacityFrames * channels
        var power = 1
        while power < cap { power *= 2 }
        self.capacity = power
        self.mask = power - 1
        self.buffer = .allocate(capacity: power)
        self.buffer.initialize(repeating: 0.0, count: power)
    }

    deinit { buffer.deallocate() }

    var availableToRead: Int {
        return Int(_writeHead &- _readHead)
    }

    func write(_ data: UnsafePointer<Float>, count: Int) {
        for i in 0..<count {
            buffer[Int(_writeHead) & mask] = data[i]
            _writeHead &+= 1
        }
    }

    func read(_ dest: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let avail = availableToRead
        let toRead = min(count, avail)
        for i in 0..<toRead {
            dest[i] = buffer[Int(_readHead) & mask]
            _readHead &+= 1
        }
        return toRead
    }
}
