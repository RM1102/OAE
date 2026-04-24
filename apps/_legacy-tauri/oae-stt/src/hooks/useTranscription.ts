import { useEffect, useRef, useState } from "react";
import type { SegmentPayload } from "../lib/types";
import { events } from "../lib/tauri";

export function useTranscription() {
  const [segments, setSegments] = useState<SegmentPayload[]>([]);
  const [progress, setProgress] = useState<{ processedMs: number; totalMs: number } | null>(
    null,
  );
  const [fullText, setFullText] = useState("");
  const [micLevel, setMicLevel] = useState(0);
  const [isRecording, setIsRecording] = useState(false);
  const unsubs = useRef<(() => void)[]>([]);

  useEffect(() => {
    (async () => {
      const s = await events.onSegment((seg) =>
        setSegments((prev) => [...prev, seg]),
      );
      const d = await events.onDone((text) => {
        setFullText(text);
        setIsRecording(false);
      });
      const p = await events.onProgress((pp) => setProgress(pp));
      const m = await events.onMicLevel((r) => setMicLevel(r));
      unsubs.current = [s, d, p, m].map((u) => () => {
        void u();
      });
    })();
    return () => {
      unsubs.current.forEach((u) => u());
    };
  }, []);

  const clear = () => {
    setSegments([]);
    setProgress(null);
    setFullText("");
  };

  return {
    segments,
    progress,
    fullText,
    micLevel,
    isRecording,
    setIsRecording,
    clear,
    setFullText,
  };
}

