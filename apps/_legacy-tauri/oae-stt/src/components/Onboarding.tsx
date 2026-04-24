import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { commands, events } from "../lib/tauri";
import { useSettings } from "../hooks/useSettings";
import type { ModelEntry } from "../lib/types";

export function Onboarding() {
  const { t } = useTranslation();
  const { settings } = useSettings();
  const [models, setModels] = useState<ModelEntry[]>([]);
  const [hidden, setHidden] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState<{
    receivedBytes: number;
    totalBytes: number | null;
  } | null>(null);

  useEffect(() => {
    void commands.listModels().then(setModels);
    let mounted = true;
    let unsubs: Array<() => void> = [];
    void (async () => {
      const unProgress = await events.onModelDownloadProgress((p) => {
        if (!mounted || p.id !== "whisper-small") return;
        setProgress({ receivedBytes: p.receivedBytes, totalBytes: p.totalBytes });
        setError(null);
      });
      const unDone = await events.onModelDownloadDone((p) => {
        if (!mounted || p.id !== "whisper-small") return;
        setHidden(true);
      });
      const unFailed = await events.onModelDownloadFailed((p) => {
        if (!mounted || p.id !== "whisper-small") return;
        setError(p.error);
      });
      unsubs = [unProgress, unDone, unFailed].map((u) => () => void u());
    })();
    return () => {
      mounted = false;
      unsubs.forEach((u) => u());
    };
  }, []);

  if (!settings || settings.onboardingDone || hidden) return null;

  const hasHandy = models.some((m) => m.origin === "Handy");
  const isDownloading = !hasHandy && models.length === 0;
  const pct =
    progress && progress.totalBytes
      ? Math.round((progress.receivedBytes / progress.totalBytes) * 100)
      : null;

  return (
    <div className="rounded border border-cyan-800 bg-cyan-950/30 p-3 text-sm">
      <p>{hasHandy ? t("onboarding.handyDetected") : t("onboarding.noModels")}</p>
      {isDownloading && (
        <div className="mt-3 space-y-2">
          <div className="h-2 rounded bg-zinc-800 overflow-hidden">
            <div
              className="h-full bg-cyan-400 transition-all"
              style={{ width: `${pct ?? 3}%` }}
            />
          </div>
          <p className="text-xs text-zinc-300">
            {pct !== null
              ? `Downloading small model: ${pct}%`
              : "Downloading small model..."}
          </p>
          {error && (
            <div className="space-y-2">
              <p className="text-xs text-red-300">Download failed: {error}</p>
              <button
                className="px-2 py-1 rounded bg-zinc-800 hover:bg-zinc-700"
                onClick={async () => {
                  setError(null);
                  await commands.downloadDefaultModel();
                }}
              >
                Retry Download
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

