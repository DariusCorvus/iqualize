use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use uuid::Uuid;

use super::presets::FLAT_ID;

/// Application state, persisted to ~/.config/iqualize/state.json.
/// Mirrors the macOS iQualizeState for cross-platform compatibility.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppState {
    pub is_enabled: bool,
    pub selected_preset_id: Uuid,
    pub peak_limiter: bool,
    pub window_open: bool,
    pub max_gain_db: f32,
    pub bypassed: bool,
    pub auto_scale: bool,
    pub pre_eq_spectrum_enabled: bool,
    pub post_eq_spectrum_enabled: bool,
    pub start_at_login: bool,
    pub balance: f32,
    pub split_channel_enabled: bool,
    pub active_channel: Option<String>,
    pub input_gain_db: f32,
    pub output_gain_db: f32,
    pub show_bandwidth_as_q: bool,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            is_enabled: false,
            selected_preset_id: FLAT_ID,
            peak_limiter: true,
            window_open: false,
            max_gain_db: 12.0,
            bypassed: false,
            auto_scale: true,
            pre_eq_spectrum_enabled: false,
            post_eq_spectrum_enabled: false,
            start_at_login: false,
            balance: 0.0,
            split_channel_enabled: false,
            active_channel: None,
            input_gain_db: 0.0,
            output_gain_db: 0.0,
            show_bandwidth_as_q: true,
        }
    }
}

fn config_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("iqualize")
}

fn state_path() -> PathBuf {
    config_dir().join("state.json")
}

fn presets_path() -> PathBuf {
    config_dir().join("custom_presets.json")
}

impl AppState {
    pub fn load() -> Self {
        let path = state_path();
        match fs::read_to_string(&path) {
            Ok(data) => serde_json::from_str(&data).unwrap_or_default(),
            Err(_) => Self::default(),
        }
    }

    pub fn save(&self) -> Result<(), String> {
        let dir = config_dir();
        fs::create_dir_all(&dir).map_err(|e| format!("Failed to create config dir: {e}"))?;
        let data =
            serde_json::to_string_pretty(self).map_err(|e| format!("Failed to serialize: {e}"))?;
        fs::write(state_path(), data).map_err(|e| format!("Failed to write state: {e}"))?;
        Ok(())
    }
}

/// Custom preset store, persisted to ~/.config/iqualize/custom_presets.json.
use crate::dsp::biquad::EQBand;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EQPresetData {
    pub id: Uuid,
    pub name: String,
    pub bands: Vec<EQBand>,
    pub right_bands: Option<Vec<EQBand>>,
    pub is_built_in: bool,
}

impl EQPresetData {
    pub fn is_split_channel(&self) -> bool {
        self.right_bands.is_some()
    }
}

pub fn load_custom_presets() -> Vec<EQPresetData> {
    let path = presets_path();
    match fs::read_to_string(&path) {
        Ok(data) => serde_json::from_str(&data).unwrap_or_default(),
        Err(_) => Vec::new(),
    }
}

pub fn save_custom_presets(presets: &[EQPresetData]) -> Result<(), String> {
    let dir = config_dir();
    fs::create_dir_all(&dir).map_err(|e| format!("Failed to create config dir: {e}"))?;
    let data = serde_json::to_string_pretty(presets)
        .map_err(|e| format!("Failed to serialize presets: {e}"))?;
    fs::write(presets_path(), data).map_err(|e| format!("Failed to write presets: {e}"))?;
    Ok(())
}
