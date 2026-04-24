import { useTranslation } from "react-i18next";
import { commands } from "../lib/tauri";
import { TranscriptView } from "./TranscriptView";
import { useTranscription } from "../hooks/useTranscription";

export function LiveTab() {
  const { t } = useTranslation();
  const tr = useTranscription();

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <button
          className={`px-4 py-2 rounded ${
            tr.isRecording ? "bg-red-700 hover:bg-red-600" : "bg-emerald-700 hover:bg-emerald-600"
          }`}
          onClick={async () => {
            if (tr.isRecording) {
              await commands.micStop();
              tr.setIsRecording(false);
            } else {
              tr.clear();
              await commands.micStart();
              tr.setIsRecording(true);
            }
          }}
        >
          {tr.isRecording ? t("live.stop") : t("live.start")}
        </button>
        <div className="w-40 h-2 rounded bg-zinc-800 overflow-hidden">
          <div
            className="h-full bg-cyan-400 transition-all"
            style={{ width: `${Math.min(100, tr.micLevel * 100)}%` }}
          />
        </div>
        <span className="text-xs text-zinc-400">{t("live.shortcutHint", { key: "Cmd+Shift+Space" })}</span>
      </div>

      <div className="flex gap-2">
        <button className="px-2 py-1 rounded bg-zinc-800" onClick={() => navigator.clipboard.writeText(tr.fullText)}>
          {t("live.copyAll")}
        </button>
        <button className="px-2 py-1 rounded bg-zinc-800" onClick={tr.clear}>
          {t("live.clear")}
        </button>
      </div>

      <TranscriptView segments={tr.segments} />
    </div>
  );
}

