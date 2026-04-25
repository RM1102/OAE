# Subtitle island (macOS)

Live subtitles use a **split feed** and **fixed-width cells** so WhisperKit tail rewrites do not reflow earlier visible words.

## Data model

| Lane | Source | Updated when |
|------|--------|----------------|
| **Confirmed** | Token list derived from WhisperKit `confirmedSegments` (same rows `DictateView` passes into `TranscriptStore.applyDictateUpdate`) | When the streaming engine commits segments |
| **Volatile** | Token list from the dictate `partial` string (unconfirmed segments + current hypothesis) | Every partial refresh |

The main Dictate transcript pane still uses merged + `stabilizedWords` confirmed text inside `TranscriptStore`; the island **does not** drive off `fullText` for layout.

Published on `TranscriptStore`:

- `subtitleConfirmedWords`, `subtitleVolatileWords`
- `subtitleFeedDictateSessionID` — must match the current dictate session; stale callbacks are ignored the same way as `applyDictateUpdate(sessionID:)`.

When the app activates a non-dictate source (`activate(.capture)` / `.file`), subtitle word arrays are cleared so the overlay never shows another mode’s bucket.

## Compositor

`SubtitleIslandCompositor` maps `(C, V)` into exactly **N** cells (`N` ∈ {12, 15, 18} via Settings / overlay picker):

- Reserve `volatileSlotCount = min(N, max(1, |V|))` when `V` is non-empty, else `0`.
- Remaining cells show the **right tail** of `C`; volatile cells show the **right tail** of `V`.
- Left confirmed cells stay stable when only `V` changes (tail revision).

**Transition labels** (for debug stats): `bootstrap`, `append`, `tailRevision`, `confirmationShift`, `reset`.

## Coalescing

`SubtitleFeedCoalescer` samples the store on a **60 Hz** main-thread timer so ASR bursts do not hammer SwiftUI. The coalescer **starts** when the overlay becomes visible and **stops** on hide / `onDisappear`.

## Settings

| Key | Meaning |
|-----|---------|
| `oae.subtitle.presentation` | `floating` or `notchStrip` |
| `oae.subtitle.chunkWords` | Segmented value 3 / 5 / 7 → island capacities 12 / 15 / 18 |
| `oae.subtitle.fontSize` | Cell text size |
| `oae.subtitle.backgroundOpacity` | Island fill alpha |
| `oae.subtitle.islandMonospace` | **Subtitle island: stable metrics (monospace)** — default off |

## Debug instrumentation

- **Compile-time (Debug builds):** `SUBTITLE_ISLAND_INSTRUMENTATION` is set in `apps/oae-mac/project.yml` so extra tooling can be `#if`’d.
- **Runtime (any build):** `defaults write computer.oae.OAE oae.subtitle.debugStats -bool YES` then watch Console for `[OAE.SubtitleIsland]` — transition counters and UI flush Hz (EMA).

## Manual QA

1. Long Dictate session with aggressive rewrites: left (confirmed) cells should not slide when the tail rewrites.
2. Continuous speech: FIFO-style advance at the live edge; boundary shifts when the engine confirms more text.
3. Toggle subtitles off/on: no crash, no stale text from a previous session.
4. Switch to Capture/File while subtitles are open: placeholder only — no foreign transcript.
