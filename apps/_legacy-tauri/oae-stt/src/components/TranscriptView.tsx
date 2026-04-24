import type { SegmentPayload } from "../lib/types";

function msToTs(ms: number) {
  const s = Math.floor(ms / 1000);
  const hh = Math.floor(s / 3600)
    .toString()
    .padStart(2, "0");
  const mm = Math.floor((s % 3600) / 60)
    .toString()
    .padStart(2, "0");
  const ss = Math.floor(s % 60)
    .toString()
    .padStart(2, "0");
  return `${hh}:${mm}:${ss}`;
}

export function TranscriptView({ segments }: { segments: SegmentPayload[] }) {
  return (
    <div className="rounded border border-zinc-800 bg-zinc-950/70 p-3 h-[52vh] overflow-auto">
      {segments.length === 0 ? (
        <p className="text-sm text-zinc-400">No transcript yet.</p>
      ) : (
        <ul className="space-y-2">
          {segments.map((s, i) => (
            <li key={`${s.startMs}-${i}`} className="text-sm">
              <span className="text-zinc-400 mr-2">
                [{msToTs(s.startMs)} → {msToTs(s.endMs)}]
              </span>
              <span>{s.text}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

