use crate::audio_toolkit::decode::decode_file_to_mono_f32;
use crate::audio_toolkit::resample::resample_mono_to_16k;
use crate::managers::model_registry::{DownloadPlan, ModelEntry, ModelOrigin, ModelRegistry};
use crate::managers::transcription::TranscriptionService;
use crate::managers::AudioService;
use crate::settings::AppSettings;
use crate::utils::{history_path, own_models_dir, resolve_silero_path};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_clipboard_manager::ClipboardExt;

pub struct AppState {
    pub registry: Arc<ModelRegistry>,
    pub transcription: Arc<TranscriptionService>,
    pub audio: Arc<AudioService>,
    pub settings: Arc<Mutex<AppSettings>>,
    pub recording: Arc<AtomicBool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
#[serde(rename_all = "camelCase")]
pub struct SileroStatus {
    pub available: bool,
    pub path: Option<String>,
}

pub fn choose_preferred_model_id(models: &[ModelEntry]) -> Option<String> {
    models
        .iter()
        .find(|m| matches!(m.origin, ModelOrigin::Handy))
        .or_else(|| models.iter().find(|m| matches!(m.origin, ModelOrigin::Local)))
        .or_else(|| models.first())
        .map(|m| m.id.clone())
}

fn download_plan_to_disk_with_progress(
    app: &AppHandle,
    plan: &DownloadPlan,
) -> Result<PathBuf, String> {
    let dest = PathBuf::from(&plan.destination_dir).join(&plan.filename);
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(3600))
        .build()
        .map_err(|e| e.to_string())?;
    let mut resp = client.get(&plan.url).send().map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("download failed: {}", resp.status()));
    }

    let total = resp.content_length();
    let mut f = std::fs::File::create(&dest).map_err(|e| e.to_string())?;
    let mut received: u64 = 0;
    let mut buf = [0u8; 256 * 1024];

    loop {
        let n = resp.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        f.write_all(&buf[..n]).map_err(|e| e.to_string())?;
        received += n as u64;
        let _ = app.emit(
            "model-download-progress",
            serde_json::json!({
                "id": plan.id,
                "receivedBytes": received,
                "totalBytes": total
            }),
        );
    }
    f.flush().map_err(|e| e.to_string())?;
    Ok(dest)
}

pub fn auto_download_default_model(
    app: AppHandle,
    registry: Arc<ModelRegistry>,
    settings: Arc<Mutex<AppSettings>>,
) -> Result<String, String> {
    let plan = registry
        .suggest_download("whisper-small")
        .map_err(|e| e.to_string())?;
    let dest = download_plan_to_disk_with_progress(&app, &plan)?;
    registry.rescan().map_err(|e| e.to_string())?;
    {
        let mut s = settings.lock();
        s.selected_model_id = Some("whisper-small".to_string());
        s.onboarding_done = true;
        s.save().map_err(|e| e.to_string())?;
    }
    let _ = app.emit("models-changed", ());
    let _ = app.emit(
        "model-download-done",
        serde_json::json!({ "id": "whisper-small", "path": dest.to_string_lossy() }),
    );
    Ok(dest.to_string_lossy().to_string())
}

#[tauri::command]
#[specta::specta]
pub fn list_models(state: State<'_, AppState>) -> Result<Vec<ModelEntry>, String> {
    state.inner().registry.rescan().map_err(|e| e.to_string())?;
    Ok(state.inner().registry.list())
}

#[tauri::command]
#[specta::specta]
pub fn refresh_models(state: State<'_, AppState>) -> Result<Vec<ModelEntry>, String> {
    state.inner().registry.rescan().map_err(|e| e.to_string())?;
    Ok(state.inner().registry.list())
}

#[tauri::command]
#[specta::specta]
pub fn resolve_model_path(state: State<'_, AppState>, id: String) -> Result<String, String> {
    state
        .inner()
        .registry
        .resolve_path(&id)
        .map(|p| p.to_string_lossy().to_string())
        .map_err(|e| e.to_string())
}

#[tauri::command]
#[specta::specta]
pub fn suggest_download(state: State<'_, AppState>, id: String) -> Result<DownloadPlan, String> {
    state.inner().registry.suggest_download(&id).map_err(|e| e.to_string())
}

#[tauri::command]
#[specta::specta]
pub fn download_model(app: AppHandle, state: State<'_, AppState>, id: String) -> Result<String, String> {
    let plan = state.inner().registry.suggest_download(&id).map_err(|e| e.to_string())?;
    let dest = download_plan_to_disk_with_progress(&app, &plan)?;
    state.inner().registry.rescan().map_err(|e| e.to_string())?;
    let _ = app.emit(
        "model-download-done",
        serde_json::json!({ "id": id, "path": dest.to_string_lossy() }),
    );
    Ok(dest.to_string_lossy().to_string())
}

#[tauri::command]
#[specta::specta]
pub fn download_default_model(app: AppHandle, state: State<'_, AppState>) -> Result<String, String> {
    auto_download_default_model(
        app,
        state.inner().registry.clone(),
        state.inner().settings.clone(),
    )
}

#[tauri::command]
#[specta::specta]
pub fn open_own_models_dir(_app: AppHandle) -> Result<(), String> {
    let p = own_models_dir().map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&p)
            .status()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn get_settings(state: State<'_, AppState>) -> AppSettings {
    state.inner().settings.lock().clone()
}

#[tauri::command]
#[specta::specta]
pub fn save_settings(state: State<'_, AppState>, settings: AppSettings) -> Result<(), String> {
    settings.save().map_err(|e| e.to_string())?;
    *state.inner().settings.lock() = settings;
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn list_mics(state: State<'_, AppState>) -> Result<Vec<String>, String> {
    state.inner().audio.list_input_devices().map_err(|e| e.to_string())
}

#[tauri::command]
#[specta::specta]
pub fn silero_status() -> SileroStatus {
    let p = resolve_silero_path();
    SileroStatus {
        available: p.is_some(),
        path: p.map(|x| x.to_string_lossy().to_string()),
    }
}

#[tauri::command]
#[specta::specta]
pub fn mic_start(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    let model_id = state.inner().settings.lock().selected_model_id.clone();
    let Some(model_id) = model_id else {
        if state.inner().registry.list().is_empty() {
            return Err("Model still downloading, please wait.".into());
        }
        return Err("no model selected".into());
    };
    state
        .inner()
        .registry
        .resolve_path(&model_id)
        .map_err(|_| "Model still downloading, please wait.".to_string())?;

    if state.inner().recording.swap(true, Ordering::SeqCst) {
        return Err("already recording".into());
    }
    let dev = state.inner().settings.lock().mic_device.clone();
    state
        .inner()
        .audio
        .start(dev, app.clone())
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn mic_stop(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    if !state.inner().recording.swap(false, Ordering::SeqCst) {
        return Err("not recording".into());
    }
    let samples = state.inner().audio.stop().map_err(|e| e.to_string())?;
    let model_id = state
        .inner()
        .settings
        .lock()
        .selected_model_id
        .clone()
        .ok_or_else(|| "no model selected".to_string())?;
    let model_path = state.inner().registry.resolve_path(&model_id).map_err(|e| e.to_string())?;
    let lang = state.inner().settings.lock().language.clone();

    let tr = state.inner().transcription.clone();
    let app2 = app.clone();

    std::thread::spawn(move || {
        if samples.is_empty() {
            let _ = app2.emit("transcription-done", serde_json::json!({ "fullText": "" }));
            return;
        }

        let chunk = 30 * 16_000usize;
        let overlap = 1 * 16_000usize;
        let total_ms = ((samples.len() as f64 / 16_000.0) * 1000.0) as u64;
        let mut full = String::new();
        let mut start = 0usize;

        while start < samples.len() {
            let end = (start + chunk).min(samples.len());
            let slice = samples[start..end].to_vec();
            let offset_sec = start as f32 / 16_000.0;
            let processed_ms = ((start as f64 / samples.len() as f64) * total_ms as f64) as u64;
            let _ = app2.emit(
                "transcription-progress",
                serde_json::json!({ "processedMs": processed_ms, "totalMs": total_ms }),
            );

            let mut result = match tr.transcribe_pcm(&slice, &model_path, lang.clone()) {
                Ok(r) => r,
                Err(e) => {
                    let _ = app2.emit(
                        "transcription-done",
                        serde_json::json!({ "fullText": format!("Transcription error: {e}") }),
                    );
                    return;
                }
            };

            if let Some(segs) = result.segments.as_mut() {
                for s in segs.iter_mut() {
                    s.start += offset_sec;
                    s.end += offset_sec;
                }
            }
            for s in TranscriptionService::result_to_segments(&result) {
                let _ = app2.emit("transcription-segment", &s);
            }
            if !result.text.is_empty() {
                if !full.is_empty() {
                    full.push(' ');
                }
                full.push_str(&result.text);
            }
            if end == samples.len() {
                break;
            }
            start = start + chunk - overlap;
        }

        let _ = app2.emit(
            "transcription-done",
            serde_json::json!({ "fullText": full.trim() }),
        );
        let _ = app2.clipboard().write_text(full.trim().to_string());
    });

    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn transcribe_file(
    app: AppHandle,
    state: State<'_, AppState>,
    path: String,
) -> Result<(), String> {
    let model_id = state
        .inner()
        .settings
        .lock()
        .selected_model_id
        .clone()
        .ok_or_else(|| "no model selected".to_string())?;
    let model_path = state.inner().registry.resolve_path(&model_id).map_err(|e| e.to_string())?;
    let lang = state.inner().settings.lock().language.clone();
    let p = PathBuf::from(path);

    let (mono, fs_in) = decode_file_to_mono_f32(&p).map_err(|e| e.to_string())?;
    let total_ms = ((mono.len() as f64 / fs_in as f64) * 1000.0) as u64;
    let mono16 = resample_mono_to_16k(&mono, fs_in).map_err(|e| e.to_string())?;

    let chunk = 30 * 16_000usize;
    let overlap = 1 * 16_000usize;
    let mut full = String::new();
    let mut start = 0usize;
    let tr = state.inner().transcription.clone();
    let app2 = app.clone();

    while start < mono16.len() {
        let end = (start + chunk).min(mono16.len());
        let slice = mono16[start..end].to_vec();
        let offset_sec = start as f32 / 16_000.0;
        let processed_ms = ((start as f64 / mono16.len() as f64) * total_ms as f64) as u64;
        let _ = app2.emit(
            "transcription-progress",
            serde_json::json!({ "processedMs": processed_ms, "totalMs": total_ms }),
        );

        let (tx, rx) = std::sync::mpsc::channel();
        let trc = tr.clone();
        let mp = model_path.clone();
        let lg = lang.clone();
        std::thread::spawn(move || {
            let r = trc.transcribe_pcm(&slice, &mp, lg);
            let _ = tx.send(r);
        });
        let mut result = rx
            .recv()
            .map_err(|_| "thread died".to_string())?
            .map_err(|e| e.to_string())?;
        if let Some(segs) = result.segments.as_mut() {
            for s in segs.iter_mut() {
                s.start += offset_sec;
                s.end += offset_sec;
            }
        }
        for s in TranscriptionService::result_to_segments(&result) {
            let _ = app2.emit("transcription-segment", &s);
        }
        if !result.text.is_empty() {
            if !full.is_empty() {
                full.push(' ');
            }
            full.push_str(&result.text);
        }
        if end == mono16.len() {
            break;
        }
        start = start + chunk - overlap;
    }

    let _ = app.emit(
        "transcription-done",
        serde_json::json!({ "fullText": full.trim() }),
    );
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn append_history(text: String) -> Result<(), String> {
    let p = history_path().map_err(|e| e.to_string())?;
    let line = serde_json::json!({ "ts": chrono_simple_now(), "text": text });
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(p)
        .map_err(|e| e.to_string())?;
    writeln!(f, "{}", line).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn list_history() -> Result<Vec<String>, String> {
    let p = history_path().map_err(|e| e.to_string())?;
    if !p.exists() {
        return Ok(vec![]);
    }
    let s = std::fs::read_to_string(p).map_err(|e| e.to_string())?;
    Ok(s.lines().map(|l| l.to_string()).collect())
}

fn chrono_simple_now() -> String {
    use std::time::SystemTime;
    format!("{:?}", SystemTime::now())
}

/// Global shortcut entry: toggle recording / transcribe.
pub fn toggle_from_hotkey(app: &AppHandle) -> Result<(), String> {
    let state = app.state::<AppState>();
    if state.inner().recording.load(Ordering::SeqCst) {
        mic_stop(app.clone(), state)?;
    } else {
        mic_start(app.clone(), state)?;
    }
    Ok(())
}
