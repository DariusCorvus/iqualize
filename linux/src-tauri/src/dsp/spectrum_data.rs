use std::sync::atomic::{AtomicI32, Ordering};

/// Lock-free double-buffered magnitude data for audio->UI transfer.
/// Writer (FFT thread) fills the inactive buffer and flips the index.
/// Reader (UI/event thread) reads from the currently active buffer.
pub struct SpectrumData {
    buffers: [Vec<f32>; 2],
    active_index: AtomicI32,
}

pub const BIN_COUNT: usize = 128;
const BUFFER_SIZE: usize = BIN_COUNT * 2; // magnitudes + peaks

// Safety: SpectrumData uses atomic operations for the index flip.
// The write side only writes to the inactive buffer, the read side
// only reads from the active buffer.
unsafe impl Send for SpectrumData {}
unsafe impl Sync for SpectrumData {}

impl SpectrumData {
    pub fn new() -> Self {
        Self {
            buffers: [vec![-90.0; BUFFER_SIZE], vec![-90.0; BUFFER_SIZE]],
            active_index: AtomicI32::new(0),
        }
    }

    /// Called from the FFT thread.
    pub fn write(&self, magnitudes: &[f32], peaks: &[f32]) {
        let write_idx = 1 - self.active_index.load(Ordering::Acquire);
        let buf = &self.buffers[write_idx as usize];
        // Safety: only one writer, writes to inactive buffer
        let ptr = buf.as_ptr() as *mut f32;
        unsafe {
            std::ptr::copy_nonoverlapping(magnitudes.as_ptr(), ptr, BIN_COUNT);
            std::ptr::copy_nonoverlapping(peaks.as_ptr(), ptr.add(BIN_COUNT), BIN_COUNT);
        }
        self.active_index.store(write_idx, Ordering::Release);
    }

    /// Called from the UI/event thread. Returns (magnitudes, peaks).
    pub fn read(&self) -> (Vec<f32>, Vec<f32>) {
        let idx = self.active_index.load(Ordering::Acquire) as usize;
        let buf = &self.buffers[idx];
        let magnitudes = buf[..BIN_COUNT].to_vec();
        let peaks = buf[BIN_COUNT..].to_vec();
        (magnitudes, peaks)
    }
}
