//! Small helpers shared across the crate.

use std::path::{Path, PathBuf};

/// Known Whisper GGML filenames used by Handy (exact match).
pub fn handy_known_id(filename: &str) -> Option<&'static str> {
    match filename {
        "ggml-small.bin" => Some("whisper-small"),
        "whisper-medium-q4_1.bin" => Some("whisper-medium"),
        "ggml-large-v3-turbo.bin" => Some("whisper-turbo"),
        "ggml-large-v3-q5_0.bin" => Some("whisper-large"),
        _ => None,
    }
}

pub fn handy_models_dir() -> Option<PathBuf> {
    dirs::data_dir().map(|d| d.join("com.pais.handy/models"))
}

pub fn own_models_dir() -> anyhow::Result<PathBuf> {
    let d = dirs::data_dir()
        .ok_or_else(|| anyhow::anyhow!("no data dir"))?
        .join("computer.oae.stt/models");
    std::fs::create_dir_all(&d)?;
    Ok(d)
}

pub fn silero_candidates() -> Vec<PathBuf> {
    let mut v = Vec::new();
    if let Some(h) = handy_models_dir() {
        v.push(h.join("silero_vad_v4.onnx"));
    }
    if let Ok(own) = own_models_dir() {
        v.push(own.join("silero_vad_v4.onnx"));
    }
    v.push(PathBuf::from("resources/models/silero_vad_v4.onnx"));
    v
}

pub fn resolve_silero_path() -> Option<PathBuf> {
    silero_candidates().into_iter().find(|p| p.exists())
}

pub fn history_path() -> anyhow::Result<PathBuf> {
    let d = dirs::data_dir()
        .ok_or_else(|| anyhow::anyhow!("no data dir"))?
        .join("computer.oae.stt");
    std::fs::create_dir_all(&d)?;
    Ok(d.join("history.jsonl"))
}

pub fn settings_path() -> anyhow::Result<PathBuf> {
    let d = dirs::data_dir()
        .ok_or_else(|| anyhow::anyhow!("no data dir"))?
        .join("computer.oae.stt");
    std::fs::create_dir_all(&d)?;
    Ok(d.join("settings.json"))
}

pub fn display_name_for_bin(filename: &str) -> String {
    if let Some(id) = handy_known_id(filename) {
        return match id {
            "whisper-small" => "Small".into(),
            "whisper-medium" => "Medium".into(),
            "whisper-turbo" => "Turbo".into(),
            "whisper-large" => "Large".into(),
            _ => id.into(),
        };
    }
    format!("custom: {}", filename.trim_end_matches(".bin"))
}

/// Download URL for known model ids (Handy blob CDN). Writes to **own** dir only.
pub fn download_url_for_id(id: &str) -> Option<&'static str> {
    match id {
        "whisper-small" => Some("https://blob.handy.computer/ggml-small.bin"),
        "whisper-medium" => Some("https://blob.handy.computer/whisper-medium-q4_1.bin"),
        "whisper-turbo" => Some("https://blob.handy.computer/ggml-large-v3-turbo.bin"),
        "whisper-large" => Some("https://blob.handy.computer/ggml-large-v3-q5_0.bin"),
        _ => None,
    }
}

pub fn download_filename_for_id(id: &str) -> Option<&'static str> {
    match id {
        "whisper-small" => Some("ggml-small.bin"),
        "whisper-medium" => Some("whisper-medium-q4_1.bin"),
        "whisper-turbo" => Some("ggml-large-v3-turbo.bin"),
        "whisper-large" => Some("ggml-large-v3-q5_0.bin"),
        _ => None,
    }
}

pub fn is_bin_model(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| e.eq_ignore_ascii_case("bin"))
        .unwrap_or(false)
}
