mod audio_toolkit;
mod commands;
mod managers;
mod settings;
mod utils;

use crate::commands::{
    append_history, download_model, get_settings, list_history, list_mics, list_models, mic_start,
    mic_stop, open_own_models_dir, refresh_models, resolve_model_path, save_settings, silero_status,
    suggest_download, transcribe_file, AppState, download_default_model,
};
use crate::managers::{AudioService, ModelRegistry, TranscriptionService};
use crate::settings::AppSettings;
use parking_lot::Mutex;
use specta_typescript::Typescript;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Emitter, Manager};
use tauri_specta::{collect_commands, Builder};
use transcribe_rs::{set_whisper_accelerator, WhisperAccelerator};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    if std::env::args().any(|a| a == "--print-paths") {
        eprintln!(
            "models (own): {:?}",
            utils::own_models_dir().unwrap_or_default()
        );
        eprintln!("models (handy): {:?}", utils::handy_models_dir());
        return;
    }

    set_whisper_accelerator(WhisperAccelerator::Auto);

    let specta_builder = Builder::<tauri::Wry>::new().commands(collect_commands![
        list_models,
        refresh_models,
        resolve_model_path,
        suggest_download,
        download_model,
        download_default_model,
        open_own_models_dir,
        get_settings,
        save_settings,
        list_mics,
        silero_status,
        mic_start,
        mic_stop,
        transcribe_file,
        append_history,
        list_history,
    ]);

    #[cfg(debug_assertions)]
    specta_builder
        .export(
            Typescript::default(),
            std::path::Path::new("../src/bindings.ts"),
        )
        .expect("failed to export typescript bindings");

    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::new().build())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_macos_permissions::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_shortcut("Command+Shift+Space")
                .expect("shortcut parse")
                .with_handler(|app, _shortcut, _event| {
                    let _ = commands::toggle_from_hotkey(app);
                })
                .build(),
        )
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.show();
                let _ = w.set_focus();
            }
        }))
        .setup(move |app| {
            let handle = app.handle().clone();
            let registry = Arc::new(ModelRegistry::new());
            registry.rescan().map_err(|e| e.to_string())?;
            let _ = ModelRegistry::spawn_watchers(handle.clone());
            let settings = Arc::new(Mutex::new(AppSettings::load()));

            let state = AppState {
                registry: registry.clone(),
                transcription: Arc::new(TranscriptionService::new()),
                audio: Arc::new(AudioService::new()),
                settings: settings.clone(),
                recording: Arc::new(AtomicBool::new(false)),
            };
            app.manage(state);

            if settings.lock().selected_model_id.is_none() {
                let models = registry.list();
                if let Some(id) = commands::choose_preferred_model_id(&models) {
                    let mut s = settings.lock();
                    s.selected_model_id = Some(id);
                    let _ = s.save();
                } else {
                    let app_handle = handle.clone();
                    let registry_clone = registry.clone();
                    let settings_clone = settings.clone();
                    std::thread::spawn(move || {
                        if let Err(e) = commands::auto_download_default_model(
                            app_handle.clone(),
                            registry_clone,
                            settings_clone,
                        ) {
                            let _ = app_handle.emit(
                                "model-download-failed",
                                serde_json::json!({ "id": "whisper-small", "error": e }),
                            );
                        }
                    });
                }
            }

            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "Show", true, None::<&str>)?;
            let toggle = MenuItem::with_id(app, "toggle", "Toggle Recording", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &toggle, &quit])?;
            let mut tray = TrayIconBuilder::new()
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "toggle" => {
                        let _ = commands::toggle_from_hotkey(app);
                    }
                    "show" => {
                        if let Some(w) = app.get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            let _tray = tray.build(app)?;

            let _ = handle.emit("models-changed", ());
            Ok(())
        })
        .invoke_handler(specta_builder.invoke_handler())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
