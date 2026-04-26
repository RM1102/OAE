# Subtitle Island (Classic stable — one line)

This document describes the live subtitle model for the macOS floating island / notch strip.

## Goals

- Keep subtitles readable under streaming ASR rewrites.
- Keep confirmed text visually anchored when only the tail rewrites.
- Avoid high-frequency micro-jitter from rapid interim updates.
- Show subtitle feed only during Dictate.
- **One line only**: a single visible caption row with per-token volatile dimming.
- **Single change kind per publish**: `confirmUpgrade` (opacity/volatile → confirmed) vs `lineRoll` / `tailRevision` are spaced by a short inter-change lag so they never land in the same UI tick.

## Feed model

`TranscriptStore` publishes a Dictate-specific subtitle feed:

- `subtitleConfirmedWords`: words derived from streaming confirmed segments.
- `subtitleVolatileWords`: words derived from unconfirmed + current partial text.
- `subtitleFeedDictateSessionID`: session guard used to ignore stale updates.

The overlay does not layout from `fullText`.

## Compositor

`SubtitleLineCompositor` consumes `(confirmed, volatile)` and produces a **one-line** snapshot:

- `tokens`: visible suffix of confirmed + volatile (length capped by cadence, typically **7**, up to **8** under burst).
- `boundaryIndex`: first volatile index inside `tokens`.
- `transition` classification: `liveFill`, `lineCommitted`, `lineRoll`, `tailRevision`, `confirmationShift`, `reset`.
- `changeKind` is assigned by the cadence controller when publishing (`idle` from compositor until then).

There is no line wrap or second row; shorter end-of-phrase tails simply use fewer than seven tokens.

## Cadence and hysteresis

`SubtitleLineCadenceController` controls UI updates:

- max commit cadence: ~60 Hz timer, publishes only when gated snapshot changes.
- debounce / volatile throttle / tail rewrite cooldown / line commit hold (pace-dependent).
- **Adaptive 7/8**: prefers seven visible words; when volatile append bursts exceed a threshold inside ~450 ms, the window allows eight words (capped by `maxVisibleWordsCap` from the overlay).
- **Inter-change lag** (~220–320 ms depending on pace): after a `confirmUpgrade` publish, a `lineRoll` / `tailRevision` is deferred until the lag elapses, and vice versa.
- one-rewrite-per-volatile-index limiter + filler-word suppression for noisy tails.

## Settings

- `oae.subtitle.presentation`: floating / top notch strip.
- `oae.subtitle.captionStyle`: currently `classicStable` (one line).
- `oae.subtitle.islandMonospace`: optional stable metrics mode (default off).
- `oae.subtitle.paceMode`: `lectureStable` (default) vs `realtimeFaster`.

## Instrumentation

Debug logs are gated by:

- compile flag: `SUBTITLE_ISLAND_INSTRUMENTATION` (Debug config)
- runtime key: `oae.subtitle.debugStats`

When enabled, logs include transition counts, **changeKind** counts, and UI update rate (EMA).

## Manual acceptance checklist

1. Long dictation with aggressive rewrites: confirmed words remain visually stable.
2. Continuous speech: FIFO progression without chaotic jumping; no second line.
3. Overlay hide/show repeatedly: no stale text or crashes.
4. Switch away from Dictate: overlay shows placeholder/blank and does not leak Capture/File text.
5. End of short phrase: fewer than seven words display without padding.
6. Logs: no `confirmUpgrade` and `lineRoll` **counts** incrementing on the same flush line (they serialize across ticks).
