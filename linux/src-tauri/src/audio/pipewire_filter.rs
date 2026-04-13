use crate::dsp::biquad::{BiquadFilterChain, EQBand};
use crate::dsp::fft::SpectrumAnalyzer;
use crate::dsp::limiter::PeakLimiter;
use crate::dsp::ring_buffer::AudioRingBuffer;
use crate::dsp::spectrum_data::SpectrumData;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

const DEFAULT_SAMPLE_RATE: f64 = 48000.0;
const RING_BUFFER_SECONDS: f64 = 0.5;

/// Shared state between the audio processing thread and the Tauri command layer.
pub struct AudioEngineState {
    // EQ parameters (written by UI, read by audio thread)
    pub left_bands: Mutex<Vec<EQBand>>,
    pub right_bands: Mutex<Option<Vec<EQBand>>>,
    pub input_gain_db: AtomicF32,
    pub output_gain_db: AtomicF32,
    pub balance: AtomicF32,
    pub bypassed: AtomicBool,
    pub peak_limiter_enabled: AtomicBool,
    pub split_channel: AtomicBool,

    // Spectrum data (written by FFT thread, read by UI)
    pub pre_eq_spectrum: Arc<SpectrumData>,
    pub post_eq_spectrum: Arc<SpectrumData>,
    pub pre_eq_enabled: AtomicBool,
    pub post_eq_enabled: AtomicBool,

    // Audio state
    pub sample_rate: AtomicU32,
    pub running: AtomicBool,
    pub output_device_name: Mutex<String>,

    // Signal to update coefficients
    pub coefficients_dirty: AtomicBool,
}

/// Atomic f32 wrapper using AtomicU32 bit reinterpretation.
pub struct AtomicF32(AtomicU32);

impl AtomicF32 {
    pub fn new(val: f32) -> Self {
        Self(AtomicU32::new(val.to_bits()))
    }

    pub fn load(&self) -> f32 {
        f32::from_bits(self.0.load(Ordering::Relaxed))
    }

    pub fn store(&self, val: f32) {
        self.0.store(val.to_bits(), Ordering::Relaxed);
    }
}

impl AudioEngineState {
    pub fn new() -> Arc<Self> {
        let pre_eq = Arc::new(SpectrumData::new());
        let post_eq = Arc::new(SpectrumData::new());
        Arc::new(Self {
            left_bands: Mutex::new(Vec::new()),
            right_bands: Mutex::new(None),
            input_gain_db: AtomicF32::new(0.0),
            output_gain_db: AtomicF32::new(0.0),
            balance: AtomicF32::new(0.0),
            bypassed: AtomicBool::new(false),
            peak_limiter_enabled: AtomicBool::new(true),
            split_channel: AtomicBool::new(false),
            pre_eq_spectrum: pre_eq,
            post_eq_spectrum: post_eq,
            pre_eq_enabled: AtomicBool::new(false),
            post_eq_enabled: AtomicBool::new(false),
            sample_rate: AtomicU32::new(DEFAULT_SAMPLE_RATE as u32),
            running: AtomicBool::new(false),
            output_device_name: Mutex::new("Default".to_string()),
            coefficients_dirty: AtomicBool::new(true),
        })
    }
}

/// The PipeWire audio engine.
///
/// On Linux, this creates a PipeWire filter node that inserts itself into the
/// audio graph as the default sink. All application audio flows through the filter,
/// gets EQ processing applied, and is forwarded to the real hardware output.
///
/// The actual PipeWire integration requires libpipewire at runtime. This module
/// provides the full architecture with a compile-time feature gate.
pub struct AudioEngine {
    pub state: Arc<AudioEngineState>,
    audio_thread: Option<thread::JoinHandle<()>>,
    fft_thread: Option<thread::JoinHandle<()>>,
    shutdown: Arc<AtomicBool>,
}

impl AudioEngine {
    pub fn new(state: Arc<AudioEngineState>) -> Self {
        Self {
            state,
            audio_thread: None,
            fft_thread: None,
            shutdown: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Start the audio engine. Spawns the PipeWire filter thread and FFT processing thread.
    pub fn start(&mut self) -> Result<(), String> {
        if self.state.running.load(Ordering::Relaxed) {
            return Ok(());
        }

        self.shutdown.store(false, Ordering::Relaxed);
        let state = self.state.clone();
        let shutdown = self.shutdown.clone();

        // Pre/post EQ ring buffers for spectrum analysis
        let sample_rate = state.sample_rate.load(Ordering::Relaxed) as f64;
        let ring_capacity = (RING_BUFFER_SECONDS * sample_rate) as usize;
        let pre_eq_ring = Arc::new(AudioRingBuffer::new(ring_capacity, 1));
        let post_eq_ring = Arc::new(AudioRingBuffer::new(ring_capacity, 1));

        // Spawn the PipeWire audio processing thread
        let pre_eq_ring_writer = pre_eq_ring.clone();
        let post_eq_ring_writer = post_eq_ring.clone();
        let audio_state = state.clone();
        let audio_shutdown = shutdown.clone();

        self.audio_thread = Some(thread::spawn(move || {
            run_pipewire_filter(audio_state, audio_shutdown, pre_eq_ring_writer, post_eq_ring_writer);
        }));

        // Spawn the FFT processing thread
        let fft_state = state.clone();
        let fft_shutdown = shutdown.clone();

        self.fft_thread = Some(thread::spawn(move || {
            run_fft_thread(fft_state, fft_shutdown, pre_eq_ring, post_eq_ring);
        }));

        self.state.running.store(true, Ordering::Relaxed);
        Ok(())
    }

    pub fn stop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Some(handle) = self.audio_thread.take() {
            let _ = handle.join();
        }
        if let Some(handle) = self.fft_thread.take() {
            let _ = handle.join();
        }
        self.state.running.store(false, Ordering::Relaxed);
    }
}

impl Drop for AudioEngine {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Run the PipeWire filter node. This is the main audio processing loop.
///
/// Architecture: Creates a PipeWire filter that acts as a pass-through node.
/// When PipeWire routes audio through it, the process callback applies EQ
/// processing in-place.
fn run_pipewire_filter(
    state: Arc<AudioEngineState>,
    shutdown: Arc<AtomicBool>,
    pre_eq_ring: Arc<AudioRingBuffer>,
    post_eq_ring: Arc<AudioRingBuffer>,
) {
    // Initialize PipeWire
    pipewire::init();

    let mainloop = pipewire::main_loop::MainLoop::new(None)
        .expect("Failed to create PipeWire main loop");
    let context = pipewire::context::Context::new(&mainloop)
        .expect("Failed to create PipeWire context");
    let core = context
        .connect(None)
        .expect("Failed to connect to PipeWire");

    // Create processing state
    let sample_rate = state.sample_rate.load(Ordering::Relaxed) as f64;
    let left_bands = state.left_bands.lock().unwrap().clone();
    let right_bands_opt = state.right_bands.lock().unwrap().clone();

    let mut left_chain = BiquadFilterChain::new(&left_bands, sample_rate);
    let mut right_chain = BiquadFilterChain::new(
        right_bands_opt.as_deref().unwrap_or(&left_bands),
        sample_rate,
    );
    let mut limiter = PeakLimiter::new(sample_rate);

    // Create the filter
    let filter = pipewire::filter::Filter::new(&core, "iQualize-EQ", pipewire::properties! {
        *pipewire::keys::MEDIA_TYPE => "Audio",
        *pipewire::keys::MEDIA_CATEGORY => "Filter",
        *pipewire::keys::MEDIA_ROLE => "DSP",
        *pipewire::keys::NODE_NAME => "iqualize_eq",
        *pipewire::keys::NODE_DESCRIPTION => "iQualize Equalizer",
        "filter.graph" => r#"{ "nodes": [] }"#,
    })
    .expect("Failed to create PipeWire filter");

    // Add input and output ports
    let _in_port_l: pipewire::filter::Port = filter
        .add_port(
            pipewire::spa::utils::Direction::Input,
            pipewire::filter::PortFlags::MAP_BUFFERS,
            std::mem::size_of::<f32>() as u32,
            pipewire::properties! {
                *pipewire::keys::FORMAT_DSP => "32 bit float mono audio",
                *pipewire::keys::PORT_NAME => "input_FL",
                "audio.channel" => "FL",
            },
        )
        .expect("Failed to add input FL port");

    let _in_port_r: pipewire::filter::Port = filter
        .add_port(
            pipewire::spa::utils::Direction::Input,
            pipewire::filter::PortFlags::MAP_BUFFERS,
            std::mem::size_of::<f32>() as u32,
            pipewire::properties! {
                *pipewire::keys::FORMAT_DSP => "32 bit float mono audio",
                *pipewire::keys::PORT_NAME => "input_FR",
                "audio.channel" => "FR",
            },
        )
        .expect("Failed to add input FR port");

    let _out_port_l: pipewire::filter::Port = filter
        .add_port(
            pipewire::spa::utils::Direction::Output,
            pipewire::filter::PortFlags::MAP_BUFFERS,
            std::mem::size_of::<f32>() as u32,
            pipewire::properties! {
                *pipewire::keys::FORMAT_DSP => "32 bit float mono audio",
                *pipewire::keys::PORT_NAME => "output_FL",
                "audio.channel" => "FL",
            },
        )
        .expect("Failed to add output FL port");

    let _out_port_r: pipewire::filter::Port = filter
        .add_port(
            pipewire::spa::utils::Direction::Output,
            pipewire::filter::PortFlags::MAP_BUFFERS,
            std::mem::size_of::<f32>() as u32,
            pipewire::properties! {
                *pipewire::keys::FORMAT_DSP => "32 bit float mono audio",
                *pipewire::keys::PORT_NAME => "output_FR",
                "audio.channel" => "FR",
            },
        )
        .expect("Failed to add output FR port");

    // Process callback
    let process_state = state.clone();
    let process_shutdown = shutdown.clone();

    filter
        .connect(
            pipewire::filter::FilterFlags::RT_PROCESS,
            move |filter_ref| {
                if process_shutdown.load(Ordering::Relaxed) {
                    return;
                }

                // Get buffers from ports
                let in_left = filter_ref.get_dsp_buffer::<f32>(0, 0);
                let in_right = filter_ref.get_dsp_buffer::<f32>(1, 0);
                let out_left = filter_ref.get_dsp_buffer_mut::<f32>(2, 0);
                let out_right = filter_ref.get_dsp_buffer_mut::<f32>(3, 0);

                let (Some(in_l), Some(in_r), Some(out_l), Some(out_r)) =
                    (in_left, in_right, out_left, out_right)
                else {
                    return;
                };

                let frame_count = in_l.len().min(in_r.len()).min(out_l.len()).min(out_r.len());

                // Copy input to output
                out_l[..frame_count].copy_from_slice(&in_l[..frame_count]);
                out_r[..frame_count].copy_from_slice(&in_r[..frame_count]);

                // Feed pre-EQ spectrum (mono mix)
                if process_state.pre_eq_enabled.load(Ordering::Relaxed) {
                    let mut mono = vec![0.0f32; frame_count];
                    for i in 0..frame_count {
                        mono[i] = (out_l[i] + out_r[i]) * 0.5;
                    }
                    pre_eq_ring.write(&mono);
                }

                if process_state.bypassed.load(Ordering::Relaxed) {
                    return;
                }

                // Check if coefficients need updating
                if process_state.coefficients_dirty.load(Ordering::Relaxed) {
                    let sr = process_state.sample_rate.load(Ordering::Relaxed) as f64;
                    if let Ok(bands) = process_state.left_bands.lock() {
                        left_chain.update_coefficients(&bands, sr);
                    }
                    if process_state.split_channel.load(Ordering::Relaxed) {
                        if let Ok(rb) = process_state.right_bands.lock() {
                            if let Some(ref bands) = *rb {
                                right_chain.update_coefficients(bands, sr);
                            }
                        }
                    } else if let Ok(bands) = process_state.left_bands.lock() {
                        right_chain.update_coefficients(&bands, sr);
                    }
                    process_state.coefficients_dirty.store(false, Ordering::Relaxed);
                }

                // Apply input gain
                let input_gain = db_to_linear(process_state.input_gain_db.load());
                if (input_gain - 1.0).abs() > 1e-6 {
                    for i in 0..frame_count {
                        out_l[i] *= input_gain;
                        out_r[i] *= input_gain;
                    }
                }

                // Apply EQ
                left_chain.process(&mut out_l[..frame_count]);
                right_chain.process(&mut out_r[..frame_count]);

                // Apply peak limiter
                if process_state.peak_limiter_enabled.load(Ordering::Relaxed) {
                    limiter.process_stereo(
                        &mut out_l[..frame_count],
                        &mut out_r[..frame_count],
                    );
                }

                // Apply output gain
                let output_gain = db_to_linear(process_state.output_gain_db.load());
                if (output_gain - 1.0).abs() > 1e-6 {
                    for i in 0..frame_count {
                        out_l[i] *= output_gain;
                        out_r[i] *= output_gain;
                    }
                }

                // Apply balance
                let bal = process_state.balance.load();
                if bal.abs() > 0.01 {
                    let (l_gain, r_gain) = if bal < 0.0 {
                        (1.0, 1.0 + bal)
                    } else {
                        (1.0 - bal, 1.0)
                    };
                    for i in 0..frame_count {
                        out_l[i] *= l_gain;
                        out_r[i] *= r_gain;
                    }
                }

                // Feed post-EQ spectrum (mono mix)
                if process_state.post_eq_enabled.load(Ordering::Relaxed) {
                    let mut mono = vec![0.0f32; frame_count];
                    for i in 0..frame_count {
                        mono[i] = (out_l[i] + out_r[i]) * 0.5;
                    }
                    post_eq_ring.write(&mono);
                }
            },
        )
        .expect("Failed to connect PipeWire filter");

    // Check for shutdown periodically
    let loop_shutdown = shutdown.clone();
    let timer = mainloop.add_timer(move |_| {
        if loop_shutdown.load(Ordering::Relaxed) {
            // The mainloop will be quit externally
        }
    });
    // Update timer to fire every 100ms
    timer.update_timer(
        &pipewire::spa::utils::Duration::from_millis(100),
        &pipewire::spa::utils::Duration::from_millis(100),
    );

    // Run the main loop until shutdown
    while !shutdown.load(Ordering::Relaxed) {
        mainloop.iterate(std::time::Duration::from_millis(100));
    }

    // Cleanup happens on drop
    drop(filter);
    drop(core);
    drop(context);
    pipewire::deinit();
}

/// FFT processing thread. Reads audio from ring buffers and computes spectrums.
fn run_fft_thread(
    state: Arc<AudioEngineState>,
    shutdown: Arc<AtomicBool>,
    pre_eq_ring: Arc<AudioRingBuffer>,
    post_eq_ring: Arc<AudioRingBuffer>,
) {
    let mut pre_analyzer = SpectrumAnalyzer::new();
    let mut post_analyzer = SpectrumAnalyzer::new();

    // Share spectrum data with the state
    // Note: we swap the spectrum data Arc references
    // This is safe because we set them before the UI starts reading
    let pre_spectrum = pre_analyzer.spectrum_data.clone();
    let post_spectrum = post_analyzer.spectrum_data.clone();

    // Store references in a way the UI can access
    // The UI reads from state.pre_eq_spectrum and state.post_eq_spectrum
    // We need to redirect those to our analyzer's data.
    // Since we can't reassign Arc fields, we'll read from the analyzers
    // and write to the state's spectrum data.

    while !shutdown.load(Ordering::Relaxed) {
        let sample_rate = state.sample_rate.load(Ordering::Relaxed) as f64;

        if state.pre_eq_enabled.load(Ordering::Relaxed) {
            pre_analyzer.process_from_ring_buffer(&pre_eq_ring, sample_rate);
            // Copy to shared state
            let (mags, peaks) = pre_spectrum.read();
            state.pre_eq_spectrum.write(&mags, &peaks);
        }

        if state.post_eq_enabled.load(Ordering::Relaxed) {
            post_analyzer.process_from_ring_buffer(&post_eq_ring, sample_rate);
            let (mags, peaks) = post_spectrum.read();
            state.post_eq_spectrum.write(&mags, &peaks);
        }

        // ~43ms between FFT frames (2048 samples at 48kHz ≈ 42.7ms)
        thread::sleep(std::time::Duration::from_millis(40));
    }
}

#[inline]
fn db_to_linear(db: f32) -> f32 {
    10.0_f32.powf(db / 20.0)
}
