import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { commands } from "../lib/tauri";
import { useTranscription } from "../hooks/useTranscription";
import { TranscriptView } from "./TranscriptView";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";

function toSrt(segments: { startMs: number; endMs: number; text: string }[]) {
  const fmt = (ms: number) => {
    const h = Math.floor(ms / 3600000)
      .toString()
      .padStart(2, "0");
    const m = Math.floor((ms % 3600000) / 60000)
      .toString()
      .padStart(2, "0");
    const s = Math.floor((ms % 60000) / 1000)
      .toString()
      .padStart(2, "0");
    const ms3 = Math.floor(ms % 1000)
      .toString()
      .padStart(3, "0");
    return `${h}:${m}:${s},${ms3}`;
  };
  return segments
    .map((x, i) => `${i + 1}\n${fmt(x.startMs)} --> ${fmt(x.endMs)}\n${x.text}\n`)
    .join("\n");
}

function download(name: string, text: string) {
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const u = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = u;
  a.download = name;
  a.click();
  URL.revokeObjectURL(u);
}

export function FileTab() {
  const { t } = useTranslation();
  const tr = useTranscription();
  const [busy, setBusy] = useState(false);
  const dropRef = useRef<HTMLDivElement | null>(null);

  const run = async (path: string) => {
    tr.clear();
    setBusy(true);
    try {
      await commands.transcribeFile(path);
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    void getCurrentWebviewWindow()
      .onDragDropEvent((event) => {
        if (event.payload.type !== "drop") return;
        const zone = dropRef.current;
        if (!zone) return;
        const rect = zone.getBoundingClientRect();
        const x = event.payload.position.x;
        const y = event.payload.position.y;
        const inside = x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
        if (!inside) return;
        const first = event.payload.paths[0];
        if (first) void run(first);
      })
      .then((u) => {
        unlisten = u;
      });
    return () => {
      if (unlisten) {
        void unlisten();
      }
    };
  }, []);

  return (
    <div className="space-y-3">
      <div
        ref={dropRef}
        className="border border-dashed border-zinc-700 rounded p-6 text-center bg-zinc-950/50"
      >
        <p className="text-zinc-300">{t("file.drop")}</p>
        <button
          className="mt-2 px-3 py-1 rounded bg-zinc-800 hover:bg-zinc-700"
          onClick={async () => {
            const p = await open({
              multiple: false,
              filters: [{ name: "Audio", extensions: ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aac"] }],
            });
            if (typeof p === "string") await run(p);
          }}
        >
          {t("file.pick")}
        </button>
      </div>

      {tr.progress && (
        <p className="text-sm text-zinc-400">
          {t("file.progress", {
            pct: Math.round((tr.progress.processedMs / Math.max(1, tr.progress.totalMs)) * 100),
          })}
        </p>
      )}
      <div className="flex gap-2">
        <button
          className="px-2 py-1 rounded bg-zinc-800"
          disabled={busy}
          onClick={() => download("transcript.txt", tr.fullText)}
        >
          {t("file.exportTxt")}
        </button>
        <button
          className="px-2 py-1 rounded bg-zinc-800"
          disabled={busy}
          onClick={() => download("transcript.srt", toSrt(tr.segments))}
        >
          {t("file.exportSrt")}
        </button>
      </div>

      <TranscriptView segments={tr.segments} />
    </div>
  );
}

