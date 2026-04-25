# Subtitle Island (Classic Stable 2-line)

This document describes the current live subtitle model for the macOS floating island.

## Goals

- Keep subtitles readable under streaming ASR rewrites.
- Keep confirmed text visually anchored when only the tail rewrites.
- Avoid high-frequency micro-jitter from rapid interim updates.
- Show subtitle feed only during Dictate.

## Feed model

`TranscriptStore` publishes a Dictate-specific subtitle feed:

- `subtitleConfirmedWords`: words derived from streaming confirmed segments.
- `subtitleVolatileWords`: words derived from unconfirmed + current partial text.
- `subtitleFeedDictateSessionID`: session guard used to ignore stale updates.

The overlay does not layout from `fullText`.

## Compositor

`SubtitleLineCompositor` consumes `(confirmed, volatile)` and produces a two-line snapshot:

- `line1` / `line2` token arrays with per-token volatile markers.
- `boundaryIndex` separating confirmed vs volatile tokens in the visible window.
- transition classification:
  - `bootstrap`
  - `append`
  - `tailRevision`
  - `confirmationShift`
  - `reset`

The compositor keeps line-break hysteresis so line wrapping does not oscillate on every tick.

## Cadence and hysteresis

`SubtitleLineCadenceController` controls UI updates:

- max commit cadence: ~60 Hz.
- debounce window: ~70 ms.
- extra hysteresis for tiny volatile tail churn: if only the final token flips inside debounce window, delay one more tick.

This reduces visual flutter while preserving responsiveness.

## Settings

- `oae.subtitle.presentation`: floating / top notch strip.
- `oae.subtitle.captionStyle`: currently `classicStable`.
- `oae.subtitle.islandMonospace`: optional stable metrics mode (default off).
- `oae.subtitle.chunkWords`: controls visible word window (12/15/18).

## Instrumentation

Debug logs are gated by:

- compile flag: `SUBTITLE_ISLAND_INSTRUMENTATION` (Debug config)
- runtime key: `oae.subtitle.debugStats`

When enabled, logs include transition counts, line-break churn, and UI update rate (EMA).

## Manual acceptance checklist

1. Long dictation with aggressive rewrites: confirmed words remain visually stable.
2. Continuous speech: FIFO progression without chaotic line jumping.
3. Overlay hide/show repeatedly: no stale text or crashes.
4. Switch away from Dictate: overlay shows placeholder/blank and does not leak Capture/File text.
