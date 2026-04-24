import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type {
  AppSettings,
  DownloadPlan,
  ModelEntry,
  SegmentPayload,
  SileroStatus,
} from "./types";

export const commands = {
  listModels: () => invoke<ModelEntry[]>("list_models"),
  refreshModels: () => invoke<ModelEntry[]>("refresh_models"),
  resolveModelPath: (id: string) =>
    invoke<string>("resolve_model_path", { id }),
  suggestDownload: (id: string) =>
    invoke<DownloadPlan>("suggest_download", { id }),
  downloadModel: (id: string) => invoke<string>("download_model", { id }),
  downloadDefaultModel: () => invoke<string>("download_default_model"),
  openOwnModelsDir: () => invoke<void>("open_own_models_dir"),
  getSettings: () => invoke<AppSettings>("get_settings"),
  saveSettings: (settings: AppSettings) =>
    invoke<void>("save_settings", { settings }),
  listMics: () => invoke<string[]>("list_mics"),
  sileroStatus: () => invoke<SileroStatus>("silero_status"),
  micStart: () => invoke<void>("mic_start"),
  micStop: () => invoke<void>("mic_stop"),
  transcribeFile: (path: string) => invoke<void>("transcribe_file", { path }),
  appendHistory: (text: string) => invoke<void>("append_history", { text }),
  listHistory: () => invoke<string[]>("list_history"),
};

export const events = {
  onSegment: (cb: (s: SegmentPayload) => void) =>
    listen<SegmentPayload>("transcription-segment", (e) => cb(e.payload)),
  onDone: (cb: (fullText: string) => void) =>
    listen<{ fullText: string }>("transcription-done", (e) => cb(e.payload.fullText)),
  onProgress: (cb: (p: { processedMs: number; totalMs: number }) => void) =>
    listen<{ processedMs: number; totalMs: number }>("transcription-progress", (e) =>
      cb(e.payload),
    ),
  onMicLevel: (cb: (rms: number) => void) =>
    listen<number>("mic-level", (e) => cb(e.payload)),
  onModelsChanged: (cb: () => void) => listen("models-changed", () => cb()),
  onModelDownloadProgress: (
    cb: (p: { id: string; receivedBytes: number; totalBytes: number | null }) => void,
  ) =>
    listen<{ id: string; receivedBytes: number; totalBytes: number | null }>(
      "model-download-progress",
      (e) => cb(e.payload),
    ),
  onModelDownloadDone: (cb: (p: { id: string; path: string }) => void) =>
    listen<{ id: string; path: string }>("model-download-done", (e) => cb(e.payload)),
  onModelDownloadFailed: (cb: (p: { id: string; error: string }) => void) =>
    listen<{ id: string; error: string }>("model-download-failed", (e) => cb(e.payload)),
};

