use std::sync::atomic::{AtomicU64, Ordering};

/// Lock-free SPSC ring buffer for bridging audio callback (producer) to FFT thread (consumer).
/// Power-of-2 capacity, wrapping integer arithmetic for correctness.
pub struct AudioRingBuffer {
    buffer: Vec<f32>,
    capacity: usize,
    mask: usize,
    write_head: AtomicU64,
    read_head: AtomicU64,
}

// Safety: the ring buffer is designed for SPSC (single producer, single consumer)
// with atomic head pointers. The buffer data is only accessed through properly
// ordered atomic operations on the head pointers.
unsafe impl Send for AudioRingBuffer {}
unsafe impl Sync for AudioRingBuffer {}

impl AudioRingBuffer {
    pub fn new(capacity_frames: usize, channels: usize) -> Self {
        let cap = capacity_frames * channels;
        let mut power = 1;
        while power < cap {
            power *= 2;
        }
        Self {
            buffer: vec![0.0; power],
            capacity: power,
            mask: power - 1,
            write_head: AtomicU64::new(0),
            read_head: AtomicU64::new(0),
        }
    }

    pub fn available_to_read(&self) -> usize {
        let w = self.write_head.load(Ordering::Acquire);
        let r = self.read_head.load(Ordering::Acquire);
        w.wrapping_sub(r) as usize
    }

    /// Write samples to the ring buffer. Called from the audio thread.
    pub fn write(&self, data: &[f32]) {
        let mut w = self.write_head.load(Ordering::Relaxed);
        for &sample in data {
            // Safety: we use interior mutability pattern here.
            // The ring buffer is SPSC - only one writer ever calls this.
            let idx = (w as usize) & self.mask;
            unsafe {
                let ptr = self.buffer.as_ptr() as *mut f32;
                *ptr.add(idx) = sample;
            }
            w = w.wrapping_add(1);
        }
        self.write_head.store(w, Ordering::Release);
    }

    /// Read samples from the ring buffer. Called from the FFT thread.
    pub fn read(&self, dest: &mut [f32]) -> usize {
        let avail = self.available_to_read();
        let to_read = dest.len().min(avail);
        let mut r = self.read_head.load(Ordering::Relaxed);
        for sample in dest[..to_read].iter_mut() {
            let idx = (r as usize) & self.mask;
            *sample = self.buffer[idx];
            r = r.wrapping_add(1);
        }
        self.read_head.store(r, Ordering::Release);
        to_read
    }
}
