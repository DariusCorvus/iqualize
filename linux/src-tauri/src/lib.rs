pub mod audio;
pub mod commands;
pub mod dsp;
pub mod state;
pub mod tray;

use audio::pipewire_filter::{AudioEngine, AudioEngineState};
use commands::AppManager;
use std::sync::Arc;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let engine_state = AudioEngineState::new();
    let manager = Arc::new(AppManager::new(engine_state.clone()));
    let mut engine = AudioEngine::new(engine_state);

    // Start the audio engine
    if let Err(e) = engine.start() {
        log::error!("Failed to start audio engine: {}", e);
    }

    let manager_for_tray = manager.clone();
    let manager_for_state = manager.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(manager.clone())
        .setup(move |app| {
            // Setup system tray
            if let Err(e) = tray::setup_tray(app.handle(), &manager_for_tray) {
                log::error!("Failed to setup tray: {}", e);
            }

            // Start spectrum event emitter
            let app_handle = app.handle().clone();
            let spectrum_manager = manager_for_state.clone();
            std::thread::spawn(move || {
                loop {
                    let pre_enabled = spectrum_manager
                        .engine_state
                        .pre_eq_enabled
                        .load(std::sync::atomic::Ordering::Relaxed);
                    let post_enabled = spectrum_manager
                        .engine_state
                        .post_eq_enabled
                        .load(std::sync::atomic::Ordering::Relaxed);

                    if pre_enabled || post_enabled {
                        let payload = commands::SpectrumPayload {
                            pre_eq: if pre_enabled {
                                let (mags, peaks) =
                                    spectrum_manager.engine_state.pre_eq_spectrum.read();
                                Some(commands::SpectrumChannelData {
                                    magnitudes: mags,
                                    peaks,
                                })
                            } else {
                                None
                            },
                            post_eq: if post_enabled {
                                let (mags, peaks) =
                                    spectrum_manager.engine_state.post_eq_spectrum.read();
                                Some(commands::SpectrumChannelData {
                                    magnitudes: mags,
                                    peaks,
                                })
                            } else {
                                None
                            },
                        };
                        let _ = app_handle.emit("spectrum-data", payload);
                    }

                    std::thread::sleep(std::time::Duration::from_millis(42));
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_state,
            commands::save_state,
            commands::get_audio_info,
            commands::set_bypass,
            commands::set_input_gain,
            commands::set_output_gain,
            commands::set_balance,
            commands::set_peak_limiter,
            commands::set_split_channel,
            commands::update_bands,
            commands::set_spectrum_enabled,
            commands::get_spectrum,
            commands::get_all_presets,
            commands::set_active_preset,
            commands::save_custom_preset,
            commands::delete_custom_preset,
            commands::import_preset,
            commands::export_preset,
        ])
        .on_window_event(|window, event| {
            // Hide window instead of closing (tray keeps the app alive)
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");

    // Cleanup
    engine.stop();
}
