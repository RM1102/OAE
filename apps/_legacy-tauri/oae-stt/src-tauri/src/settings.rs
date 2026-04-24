use serde::{Deserialize, Serialize};
use specta::Type;

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
#[serde(rename_all = "camelCase")]
pub enum ShortcutMode {
    Toggle,
    PushToTalk,
}

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub selected_model_id: Option<String>,
    pub shortcut_mode: ShortcutMode,
    /// Display string only; actual binding is fixed at build for global shortcut string.
    pub shortcut_display: String,
    pub vad_threshold: f32,
    pub auto_paste: bool,
    pub mic_device: Option<String>,
    pub language: Option<String>,
    pub onboarding_done: bool,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            selected_model_id: None,
            shortcut_mode: ShortcutMode::Toggle,
            shortcut_display: "Cmd+Shift+Space".into(),
            vad_threshold: 0.5,
            auto_paste: false,
            mic_device: None,
            language: Some("en".into()),
            onboarding_done: false,
        }
    }
}

impl AppSettings {
    pub fn load() -> Self {
        crate::utils::settings_path()
            .ok()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) -> anyhow::Result<()> {
        let p = crate::utils::settings_path()?;
        std::fs::write(p, serde_json::to_string_pretty(self)?)?;
        Ok(())
    }
}
