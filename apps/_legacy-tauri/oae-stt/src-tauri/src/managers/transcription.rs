use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::path::{Path, PathBuf};
use transcribe_rs::whisper_cpp::WhisperEngine;
use transcribe_rs::{SpeechModel, TranscribeOptions, TranscriptionResult};

#[derive(Debug, Clone, Serialize, Deserialize, Type)]
#[serde(rename_all = "camelCase")]
pub struct SegmentPayload {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

pub struct TranscriptionService {
    current: Mutex<Option<(PathBuf, WhisperEngine)>>,
}

impl TranscriptionService {
    pub fn new() -> Self {
        Self {
            current: Mutex::new(None),
        }
    }

    fn engine_for(&self, model_path: &Path) -> anyhow::Result<()> {
        let mut guard = self.current.lock();
        let need_reload = match guard.as_ref() {
            Some((p, _)) => p != model_path,
            None => true,
        };
        if need_reload {
            let eng = WhisperEngine::load(model_path)
                .map_err(|e| anyhow::anyhow!("failed to load whisper model: {e}"))?;
            *guard = Some((model_path.to_path_buf(), eng));
        }
        Ok(())
    }

    /// Full-buffer transcription (16 kHz mono f32).
    pub fn transcribe_pcm(
        &self,
        samples: &[f32],
        model_path: &Path,
        language: Option<String>,
    ) -> anyhow::Result<TranscriptionResult> {
        self.engine_for(model_path)?;
        let mut guard = self.current.lock();
        let (_, eng) = guard
            .as_mut()
            .ok_or_else(|| anyhow::anyhow!("engine not initialized"))?;
        let opts = TranscribeOptions {
            language,
            translate: false,
            leading_silence_ms: Some(0),
            trailing_silence_ms: Some(0),
        };
        let r = eng
            .transcribe(samples, &opts)
            .map_err(|e| anyhow::anyhow!("transcription failed: {e}"))?;
        Ok(r)
    }

    pub fn result_to_segments(r: &TranscriptionResult) -> Vec<SegmentPayload> {
        let Some(segs) = &r.segments else {
            return Vec::new();
        };
        segs.iter()
            .map(|s| SegmentPayload {
                start_ms: (s.start * 1000.0) as u64,
                end_ms: (s.end * 1000.0) as u64,
                text: s.text.trim().to_string(),
            })
            .filter(|s| !s.text.is_empty())
            .collect()
    }
}

impl Default for TranscriptionService {
    fn default() -> Self {
        Self::new()
    }
}
