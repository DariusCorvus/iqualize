use crate::commands::AppManager;
use crate::state::presets;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use tauri::{
    menu::{CheckMenuItemBuilder, MenuBuilder, MenuItemBuilder, SubmenuBuilder},
    tray::TrayIconBuilder,
    AppHandle, Manager,
};

pub fn setup_tray(app: &AppHandle, manager: &Arc<AppManager>) -> Result<(), Box<dyn std::error::Error>> {
    let app_state = manager.app_state.lock().unwrap();
    let is_bypassed = app_state.bypassed;
    let selected_id = app_state.selected_preset_id;
    drop(app_state);

    // Build preset submenu
    let mut preset_sub = SubmenuBuilder::new(app, "Presets");

    // Built-in presets
    let built_in = presets::built_in_presets();
    for preset in &built_in {
        let item = CheckMenuItemBuilder::new(&preset.name)
            .id(format!("preset_{}", preset.id))
            .checked(preset.id == selected_id)
            .build(app)?;
        preset_sub = preset_sub.item(&item);
    }

    // Custom presets
    let custom = manager.custom_presets.lock().unwrap().clone();
    if !custom.is_empty() {
        preset_sub = preset_sub.separator();
        for preset in &custom {
            let item = CheckMenuItemBuilder::new(&preset.name)
                .id(format!("preset_{}", preset.id))
                .checked(preset.id == selected_id)
                .build(app)?;
            preset_sub = preset_sub.item(&item);
        }
    }

    let preset_submenu = preset_sub.build(app)?;

    // Build main menu
    let open_item = MenuItemBuilder::new("Open iQualize").id("open").build(app)?;
    let bypass_item = CheckMenuItemBuilder::new("Bypass EQ")
        .id("bypass")
        .checked(is_bypassed)
        .build(app)?;

    let device_name = manager
        .engine_state
        .output_device_name
        .lock()
        .unwrap()
        .clone();
    let device_item = MenuItemBuilder::new(format!("Output: {}", device_name))
        .id("device")
        .enabled(false)
        .build(app)?;

    let about_item = MenuItemBuilder::new("About iQualize").id("about").build(app)?;
    let quit_item = MenuItemBuilder::new("Quit iQualize").id("quit").build(app)?;

    let menu = MenuBuilder::new(app)
        .item(&open_item)
        .separator()
        .item(&preset_submenu)
        .separator()
        .item(&bypass_item)
        .separator()
        .item(&device_item)
        .separator()
        .item(&about_item)
        .item(&quit_item)
        .build()?;

    let manager_clone = manager.clone();
    let _tray = TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("iQualize")
        .on_menu_event(move |app, event| {
            let id = event.id().as_ref();
            match id {
                "open" => {
                    if let Some(window) = app.get_webview_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
                "bypass" => {
                    let current = manager_clone.engine_state.bypassed.load(Ordering::Relaxed);
                    manager_clone
                        .engine_state
                        .bypassed
                        .store(!current, Ordering::Relaxed);
                    manager_clone.app_state.lock().unwrap().bypassed = !current;
                    manager_clone.save_state();
                    // Emit event to frontend
                    let _ = app.emit("bypass-changed", !current);
                }
                "about" => {
                    // Show about dialog
                    let _ = app.emit("show-about", ());
                }
                "quit" => {
                    app.exit(0);
                }
                other if other.starts_with("preset_") => {
                    let uuid_str = &other["preset_".len()..];
                    if let Ok(id) = uuid_str.parse::<uuid::Uuid>() {
                        let all: Vec<_> = presets::built_in_presets()
                            .into_iter()
                            .chain(manager_clone.custom_presets.lock().unwrap().iter().cloned())
                            .collect();
                        if let Some(preset) = all.iter().find(|p| p.id == id) {
                            *manager_clone.engine_state.left_bands.lock().unwrap() =
                                preset.bands.clone();
                            *manager_clone.engine_state.right_bands.lock().unwrap() =
                                preset.right_bands.clone();
                            manager_clone
                                .engine_state
                                .coefficients_dirty
                                .store(true, Ordering::Relaxed);
                            manager_clone.app_state.lock().unwrap().selected_preset_id = id;
                            manager_clone.save_state();
                            let _ = app.emit("preset-changed", id.to_string());
                        }
                    }
                }
                _ => {}
            }
        })
        .build(app)?;

    Ok(())
}
