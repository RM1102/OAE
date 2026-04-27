# Live subtitles (island, notch, movie)

This document describes live subtitle presentation on macOS: **floating island**, **top notch strip**, and **movie-style** lower-third captions. All modes share the same dictate feed, compositor, and cadence (see below).

## Presentation modes

| Mode | Panel | Interaction |
|------|--------|-------------|
| `floating` | Draggable island, rounded chrome | Mouse hits panel; optional position lock |
| `notchStrip` | Fixed strip under menu bar | Mouse hits panel |
| `movie` | Full **visibleFrame** clear panel; small **black** text block bottom-centered | **`ignoresMouseEvents`**: clicks pass through |

### Movie (lower third)

- **Look**: Single-line caption, **opaque black** rounded rectangle behind text, **white** copy with the same volatile (dim) vs confirmed treatment as other modes.
- **Motion**: Line **rolls** use **opacity-only** transitions (quick crossfade). No slide exit/enter like the floating island.
- **Placement** (Settings, when layout = Movie):
  - `oae.subtitle.movieInsetFromBottom` — points above the bottom of the visible frame (default ~60).
  - `oae.subtitle.movieMaxWidthFraction` — max width as fraction of screen width (0.5–0.92, default 0.72).
  - `oae.subtitle.movieHorizontalBias` — horizontal nudge from center in points (default 0).
- **Panel geometry**: `SubtitleOverlayController` sets the panel to **`NSScreen.main.visibleFrame`** so layout uses stable coordinates; only the caption block is visible.

## Goals (all modes)

- Readable under streaming ASR rewrites.
- Confirmed text anchored when only the tail rewrites.
- Avoid high-frequency micro-jitter.
- Dictate-only feed (`subtitleConfirmedWords` / `subtitleVolatileWords` / `subtitleFeedDictateSessionID`).

## Compositor and cadence

See previous sections in this file: one-line `tokens`, adaptive 7/8 window, `changeKind` gating, inter-change lag. **Unchanged** for movie mode; only **chrome and transitions** differ in `SubtitleOverlayView`.

## Settings (summary)

- `oae.subtitle.presentation`: `floating` | `notchStrip` | `movie`
- Movie placement keys (above)
- `oae.subtitle.captionStyle`, `oae.subtitle.paceMode`, `oae.subtitle.islandMonospace`

## Manual acceptance

1. **Movie**: New caption block replaces the old with a **short fade**, not a vertical slide.
2. **Movie**: Desktop clicks **miss** the overlay (pass through) except nothing is clickable—panel is clear.
3. **Movie**: Changing inset/width/bias in Settings updates live when subtitles are open.
4. Switching **presentation** while subtitles are visible rebuilds the panel without crash.
5. Floating and notch regressions: drag, lock, and strip positioning still work.
