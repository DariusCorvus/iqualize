use crate::audio::pipewire_filter::AudioEngineState;
use crate::dsp::biquad::EQBand;
use crate::state::persistence::{self, AppState, EQPresetData};
use crate::state::presets;
use serde::{Deserialize, Serialize};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

/// Manager holding all app state accessible from Tauri commands.
pub struct AppManager {
    pub engine_state: Arc<AudioEngineState>,
    pub app_state: Mutex<AppState>,
    pub custom_presets: Mutex<Vec<EQPresetData>>,
}

impl AppManager {
    pub fn new(engine_state: Arc<AudioEngineState>) -> Self {
        let app_state = AppState::load();
        let custom_presets = persistence::load_custom_presets();

        // Apply loaded state to engine
        engine_state
            .bypassed
            .store(app_state.bypassed, Ordering::Relaxed);
        engine_state
            .peak_limiter_enabled
            .store(app_state.peak_limiter, Ordering::Relaxed);
        engine_state.input_gain_db.store(app_state.input_gain_db);
        engine_state.output_gain_db.store(app_state.output_gain_db);
        engine_state.balance.store(app_state.balance);
        engine_state
            .split_channel
            .store(app_state.split_channel_enabled, Ordering::Relaxed);
        engine_state
            .pre_eq_enabled
            .store(app_state.pre_eq_spectrum_enabled, Ordering::Relaxed);
        engine_state
            .post_eq_enabled
            .store(app_state.post_eq_spectrum_enabled, Ordering::Relaxed);

        // Load active preset bands
        let all_presets: Vec<EQPresetData> = presets::built_in_presets()
            .into_iter()
            .chain(custom_presets.iter().cloned())
            .collect();
        if let Some(preset) = all_presets.iter().find(|p| p.id == app_state.selected_preset_id) {
            *engine_state.left_bands.lock().unwrap() = preset.bands.clone();
            *engine_state.right_bands.lock().unwrap() = preset.right_bands.clone();
        }
        engine_state
            .coefficients_dirty
            .store(true, Ordering::Relaxed);

        Self {
            engine_state,
            app_state: Mutex::new(app_state),
            custom_presets: Mutex::new(custom_presets),
        }
    }

    fn save_state(&self) {
        if let Ok(state) = self.app_state.lock() {
            let _ = state.save();
        }
    }

    fn all_presets(&self) -> Vec<EQPresetData> {
        let built_in = presets::built_in_presets();
        let custom = self.custom_presets.lock().unwrap().clone();
        built_in.into_iter().chain(custom.into_iter()).collect()
    }
}

// -- Tauri Commands --

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AudioInfo {
    pub sample_rate: u32,
    pub output_device: String,
    pub running: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpectrumPayload {
    pub pre_eq: Option<SpectrumChannelData>,
    pub post_eq: Option<SpectrumChannelData>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpectrumChannelData {
    pub magnitudes: Vec<f32>,
    pub peaks: Vec<f32>,
}

#[tauri::command]
pub fn get_state(manager: tauri::State<'_, Arc<AppManager>>) -> Result<AppState, String> {
    Ok(manager.app_state.lock().unwrap().clone())
}

#[tauri::command]
pub fn save_state(
    manager: tauri::State<'_, Arc<AppManager>>,
    state: AppState,
) -> Result<(), String> {
    *manager.app_state.lock().unwrap() = state.clone();
    state.save()
}

#[tauri::command]
pub fn get_audio_info(manager: tauri::State<'_, Arc<AppManager>>) -> Result<AudioInfo, String> {
    let es = &manager.engine_state;
    Ok(AudioInfo {
        sample_rate: es.sample_rate.load(Ordering::Relaxed),
        output_device: es.output_device_name.lock().unwrap().clone(),
        running: es.running.load(Ordering::Relaxed),
    })
}

#[tauri::command]
pub fn set_bypass(
    manager: tauri::State<'_, Arc<AppManager>>,
    bypassed: bool,
) -> Result<(), String> {
    manager
        .engine_state
        .bypassed
        .store(bypassed, Ordering::Relaxed);
    manager.app_state.lock().unwrap().bypassed = bypassed;
    manager.save_state();
    Ok(())
}

#[tauri::command]
pub fn set_input_gain(
    manager: tauri::State<'_, Arc<AppManager>>,
    db: f32,
) -> Result<(), String> {
    manager.engine_state.input_gain_db.store(db);
    manager.app_state.lock().unwrap().input_gain_db = db;
    manager.save_state();
    Ok(())
}

#[tauri::command]
pub fn set_output_gain(
    manager: tauri::State<'_, Arc<AppManager>>,
    db: f32,
) -> Result<(), String> {
    manager.engine_state.output_gain_db.store(db);
    manager.app_state.lock().unwrap().output_gain_db = db;
    manager.save_state();
    Ok(())
}

#[tauri::command]
pub fn set_balance(
    manager: tauri::State<'_, Arc<AppManager>>,
    value: f32,
) -> Result<(), String> {
    manager.engine_state.balance.store(value);
    manager.app_state.lock().unwrap().balance = value;
    manager.save_state();
    Ok(())
}

#[tauri::command]
pub fn set_peak_limiter(
    manager: tauri::State<'_, Arc<AppManager>>,
    enabled: bool,
) -> Result<(), String> {
    manager
        .engine_state
        .peak_limiter_enabled
        .store(enabled, Ordering::Relaxed);
    manager.app_state.lock().unwrap().peak_limiter = enabled;
    manager.save_state();
    Ok(())
}

#[tauri::command]
pub fn set_split_channel(
    manager: tauri::State<'_, Arc<AppManager>>,
    enabled: bool,
) -> Result<(), String> {
    manager
        .engine_state
        .split_channel
        .store(enabled, Ordering::Relaxed);
    if enabled {
        // Copy left bands to right if not already split
        let left = manager.engine_state.left_bands.lock().unwrap().clone();
        let mut right = manager.engine_state.right_bands.lock().unwrap();
        if right.is_none() {
            *right = Some(left);
        }
    }
    manager
        .engine_state
        .coefficients_dirty
        .store(true, Ordering::Relaxed);
    manager.app_state.lock().unwrap().split_channel_enabled = enabled;
    manager.save_state();
    Ok(())
}

#[tauri::command]
pub fn update_bands(
    manager: tauri::State<'_, Arc<AppManager>>,
    bands: Vec<EQBand>,
    channel: Option<String>,
) -> Result<(), String> {
    match channel.as_deref() {
        Some("right") => {
            *manager.engine_state.right_bands.lock().unwrap() = Some(bands);
        }
        _ => {
            *manager.engine_state.left_bands.lock().unwrap() = bands;
        }
    }
    manager
        .engine_state
        .coefficients_dirty
        .store(true, Ordering::Relaxed);
    Ok(())
}

#[tauri::command]
pub fn set_spectrum_enabled(
    manager: tauri::State<'_, Arc<AppManager>>,
    pre_eq: bool,
    post_eq: bool,
) -> Result<(), String> {
    manager
        .engine_state
        .pre_eq_enabled
        .store(pre_eq, Ordering::Relaxed);
    manager
        .engine_state
        .post_eq_enabled
        .store(post_eq, Ordering::Relaxed);
    let mut state = manager.app_state.lock().unwrap();
    state.pre_eq_spectrum_enabled = pre_eq;
    state.post_eq_spectrum_enabled = post_eq;
    drop(state);
    manager.save_state();
    Ok(())
}

#[tauri::command]
pub fn get_spectrum(
    manager: tauri::State<'_, Arc<AppManager>>,
) -> Result<SpectrumPayload, String> {
    let es = &manager.engine_state;
    let pre_eq = if es.pre_eq_enabled.load(Ordering::Relaxed) {
        let (mags, peaks) = es.pre_eq_spectrum.read();
        Some(SpectrumChannelData {
            magnitudes: mags,
            peaks,
        })
    } else {
        None
    };
    let post_eq = if es.post_eq_enabled.load(Ordering::Relaxed) {
        let (mags, peaks) = es.post_eq_spectrum.read();
        Some(SpectrumChannelData {
            magnitudes: mags,
            peaks,
        })
    } else {
        None
    };
    Ok(SpectrumPayload { pre_eq, post_eq })
}

// -- Preset Commands --

#[tauri::command]
pub fn get_all_presets(
    manager: tauri::State<'_, Arc<AppManager>>,
) -> Result<Vec<EQPresetData>, String> {
    Ok(manager.all_presets())
}

#[tauri::command]
pub fn set_active_preset(
    manager: tauri::State<'_, Arc<AppManager>>,
    id: Uuid,
) -> Result<EQPresetData, String> {
    let all = manager.all_presets();
    let preset = all
        .iter()
        .find(|p| p.id == id)
        .ok_or_else(|| "Preset not found".to_string())?
        .clone();

    *manager.engine_state.left_bands.lock().unwrap() = preset.bands.clone();
    *manager.engine_state.right_bands.lock().unwrap() = preset.right_bands.clone();
    manager
        .engine_state
        .coefficients_dirty
        .store(true, Ordering::Relaxed);

    manager.app_state.lock().unwrap().selected_preset_id = id;
    manager.save_state();

    Ok(preset)
}

#[tauri::command]
pub fn save_custom_preset(
    manager: tauri::State<'_, Arc<AppManager>>,
    preset: EQPresetData,
) -> Result<(), String> {
    let mut presets = manager.custom_presets.lock().unwrap();
    if let Some(existing) = presets.iter_mut().find(|p| p.id == preset.id) {
        *existing = preset;
    } else {
        presets.push(preset);
    }
    persistence::save_custom_presets(&presets)
}

#[tauri::command]
pub fn delete_custom_preset(
    manager: tauri::State<'_, Arc<AppManager>>,
    id: Uuid,
) -> Result<(), String> {
    let mut presets = manager.custom_presets.lock().unwrap();
    presets.retain(|p| p.id != id);
    persistence::save_custom_presets(&presets)
}

#[tauri::command]
pub fn import_preset(path: String) -> Result<EQPresetData, String> {
    let data = std::fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read file: {e}"))?;
    serde_json::from_str(&data).map_err(|e| format!("Failed to parse preset: {e}"))
}

#[tauri::command]
pub fn export_preset(
    manager: tauri::State<'_, Arc<AppManager>>,
    id: Uuid,
    path: String,
) -> Result<(), String> {
    let all = manager.all_presets();
    let preset = all
        .iter()
        .find(|p| p.id == id)
        .ok_or_else(|| "Preset not found".to_string())?;
    let data = serde_json::to_string_pretty(preset)
        .map_err(|e| format!("Failed to serialize: {e}"))?;
    std::fs::write(&path, data).map_err(|e| format!("Failed to write file: {e}"))
}
