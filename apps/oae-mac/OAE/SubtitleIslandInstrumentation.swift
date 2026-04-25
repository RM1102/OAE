import Foundation

/// Opt-in stats for subtitle compositor / coalescer (`defaults write computer.oae.OAE oae.subtitle.debugStats -bool YES`).
enum SubtitleDebugDefaults {
    static let debugStatsKey = "oae.subtitle.debugStats"
}

#if SUBTITLE_ISLAND_INSTRUMENTATION
private let instrumentationCompileTimeEnabled = true
#else
private let instrumentationCompileTimeEnabled = false
#endif

/// Lightweight counters and coalescer Hz; logs throttled when compile flag or UserDefaults enables stats.
final class SubtitleIslandInstrumentation: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [SubtitleIslandCompositor.Transition: Int] = [:]
    private var flushCount: Int = 0
    private var hzEMA: Double = 0
    private var lastLog: CFAbsoluteTime = 0
    private var lastFlushTime: CFAbsoluteTime?

    static let shared = SubtitleIslandInstrumentation()

    var isEnabled: Bool {
        if instrumentationCompileTimeEnabled { return true }
        return UserDefaults.standard.bool(forKey: SubtitleDebugDefaults.debugStatsKey)
    }

    func record(_ t: SubtitleIslandCompositor.Transition) {
        guard isEnabled else { return }
        lock.lock()
        counts[t, default: 0] += 1
        lock.unlock()
    }

    func recordFlushForHz() {
        guard isEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        flushCount += 1
        if let last = lastFlushTime {
            let dt = now - last
            if dt > 0 {
                let inst = 1.0 / dt
                hzEMA = hzEMA == 0 ? inst : (hzEMA * 0.85 + inst * 0.15)
            }
        }
        lastFlushTime = now

        let shouldLog = now - lastLog > 2.0
        if shouldLog {
            lastLog = now
            let snap = counts
            let hz = hzEMA
            let flushes = flushCount
            counts.removeAll(keepingCapacity: true)
            flushCount = 0
            lock.unlock()
            let parts = SubtitleIslandCompositor.Transition.allCases.map { "\($0.rawValue)=\(snap[$0] ?? 0)" }
            NSLog("[OAE.SubtitleIsland] transitions \(parts.joined(separator: " ")) uiHzEMA=%.1f flushes=%d", hz, flushes)
        } else {
            lock.unlock()
        }
    }
}
