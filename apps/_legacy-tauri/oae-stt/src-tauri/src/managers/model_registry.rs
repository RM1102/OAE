use crate::utils::{
    display_name_for_bin, download_filename_for_id, download_url_for_id, handy_known_id,
    handy_models_dir, is_bin_model, own_models_dir,
};
use notify::{Config, RecommendedWatcher, RecursiveMode, Watcher};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc::channel;
use std::thread;
use std::time::Duration;
use tauri::AppHandle;
use tauri::Emitter;

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
#[serde(rename_all = "camelCase")]
pub enum ModelOrigin {
    Handy,
    Local,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
#[serde(rename_all = "camelCase")]
pub struct ModelEntry {
    pub id: String,
    pub display_name: String,
    pub path: String,
    pub size_bytes: u64,
    pub origin: ModelOrigin,
}

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
#[serde(rename_all = "camelCase")]
pub struct DownloadPlan {
    pub id: String,
    pub url: String,
    pub filename: String,
    pub destination_dir: String,
}

pub struct ModelRegistry {
    inner: RwLock<Vec<ModelEntry>>,
}

impl ModelRegistry {
    pub fn new() -> Self {
        Self {
            inner: RwLock::new(Vec::new()),
        }
    }

    /// Scan Handy dir first (read-only), then own dir. Prefer Handy when same `id` exists.
    pub fn rescan(&self) -> anyhow::Result<()> {
        let mut by_id: HashMap<String, ModelEntry> = HashMap::new();

        let handy = handy_models_dir().filter(|p| p.is_dir());
        let own = own_models_dir().ok();

        // 1) Own dir first (lower priority)
        if let Some(ref dir) = own {
            self.scan_dir(dir, ModelOrigin::Local, &mut by_id)?;
        }
        // 2) Handy overwrites same id
        if let Some(ref dir) = handy {
            self.scan_dir(dir, ModelOrigin::Handy, &mut by_id)?;
        }

        let mut list: Vec<_> = by_id.into_values().collect();
        list.sort_by(|a, b| a.display_name.cmp(&b.display_name));
        *self.inner.write() = list;
        Ok(())
    }

    pub(crate) fn scan_dir(
        &self,
        dir: &Path,
        origin: ModelOrigin,
        by_id: &mut HashMap<String, ModelEntry>,
    ) -> anyhow::Result<()> {
        let rd = std::fs::read_dir(dir)?;
        for e in rd.flatten() {
            let p = e.path();
            if !p.is_file() || !is_bin_model(&p) {
                continue;
            }
            let fname = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
            let id = if let Some(k) = handy_known_id(fname) {
                k.to_string()
            } else {
                format!("custom:{fname}")
            };
            let meta = std::fs::metadata(&p)?;
            let size = meta.len();
            let display = display_name_for_bin(fname);
            let origin_tag = if id.starts_with("custom:") {
                ModelOrigin::Custom
            } else {
                origin.clone()
            };
            by_id.insert(
                id.clone(),
                ModelEntry {
                    id,
                    display_name: display,
                    path: p.to_string_lossy().to_string(),
                    size_bytes: size,
                    origin: origin_tag,
                },
            );
        }
        Ok(())
    }

    pub fn list(&self) -> Vec<ModelEntry> {
        self.inner.read().clone()
    }

    pub fn resolve_path(&self, id: &str) -> anyhow::Result<PathBuf> {
        self.inner
            .read()
            .iter()
            .find(|m| m.id == id)
            .map(|m| PathBuf::from(&m.path))
            .ok_or_else(|| anyhow::anyhow!("unknown model id: {id}"))
    }

    pub fn suggest_download(&self, id: &str) -> anyhow::Result<DownloadPlan> {
        let url = download_url_for_id(id)
            .ok_or_else(|| anyhow::anyhow!("no bundled download URL for id {id}"))?;
        let filename = download_filename_for_id(id)
            .ok_or_else(|| anyhow::anyhow!("unknown id for download: {id}"))?;
        let destination_dir = own_models_dir()?.to_string_lossy().to_string();
        Ok(DownloadPlan {
            id: id.to_string(),
            url: url.to_string(),
            filename: filename.to_string(),
            destination_dir,
        })
    }

    /// Spawn filesystem watchers on handy + own model dirs; emits `models-changed` (debounced).
    pub fn spawn_watchers(app: AppHandle) -> anyhow::Result<()> {
        let (tx, rx) = channel();
        let mut watcher = RecommendedWatcher::new(
            move |_res: notify::Result<notify::Event>| {
                let _ = tx.send(());
            },
            Config::default(),
        )?;

        if let Some(h) = handy_models_dir() {
            if h.exists() {
                watcher.watch(&h, RecursiveMode::NonRecursive)?;
            }
        }
        if let Ok(o) = own_models_dir() {
            watcher.watch(&o, RecursiveMode::NonRecursive)?;
        }

        thread::spawn(move || {
            let _keep_alive = watcher;
            while rx.recv().is_ok() {
                thread::sleep(Duration::from_millis(300));
                while rx.try_recv().is_ok() {}
                let _ = app.emit("models-changed", ());
            }
        });

        Ok(())
    }
}

impl Default for ModelRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn prefers_handy_over_own_for_same_id() {
        let root = tempdir().unwrap();
        let handy = root.path().join("handy");
        let own = root.path().join("own");
        std::fs::create_dir_all(&handy).unwrap();
        std::fs::create_dir_all(&own).unwrap();
        std::fs::write(own.join("ggml-small.bin"), vec![0u8; 8]).unwrap();
        std::fs::write(handy.join("ggml-small.bin"), vec![0u8; 16]).unwrap();

        let mut by_id = HashMap::new();
        let reg = ModelRegistry::new();
        reg.scan_dir(&own, ModelOrigin::Local, &mut by_id).unwrap();
        reg.scan_dir(&handy, ModelOrigin::Handy, &mut by_id).unwrap();
        let m = by_id.get("whisper-small").unwrap();
        assert!(matches!(m.origin, ModelOrigin::Handy));
        assert_eq!(m.size_bytes, 16);
    }
}
