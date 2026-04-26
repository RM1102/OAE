import Foundation

enum SubtitleDebugDefaults {
    static let debugStatsKey = "oae.subtitle.debugStats"
}

#if SUBTITLE_ISLAND_INSTRUMENTATION
private let subtitleInstrumentationCompileEnabled = true
#else
private let subtitleInstrumentationCompileEnabled = false
#endif

final class SubtitleIslandInstrumentation: @unchecked Sendable {
    static let shared = SubtitleIslandInstrumentation()

    private let lock = NSLock()
    private var transitionCounts: [SubtitleLineCompositor.Transition: Int] = [:]
    private var changeKindCounts: [SubtitleLineChangeKind: Int] = [:]
    private var flushCount: Int = 0
    private var hzEMA: Double = 0
    private var lastFlushAt: CFAbsoluteTime?
    private var lastLogAt: CFAbsoluteTime = 0

    var isEnabled: Bool {
        if subtitleInstrumentationCompileEnabled { return true }
        return UserDefaults.standard.bool(forKey: SubtitleDebugDefaults.debugStatsKey)
    }

    func record(snapshot: SubtitleLineSnapshot) {
        guard isEnabled else { return }
        lock.lock()
        transitionCounts[snapshot.transition, default: 0] += 1
        changeKindCounts[snapshot.changeKind, default: 0] += 1
        lock.unlock()
    }

    func recordFlush() {
        guard isEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        flushCount += 1
        if let previous = lastFlushAt {
            let dt = now - previous
            if dt > 0 {
                let hz = 1.0 / dt
                hzEMA = hzEMA == 0 ? hz : (hzEMA * 0.85 + hz * 0.15)
            }
        }
        lastFlushAt = now

        let shouldLog = now - lastLogAt > 2.0
        if shouldLog {
            lastLogAt = now
            let transitions = transitionCounts
            let kinds = changeKindCounts
            let flushes = flushCount
            let ema = hzEMA
            transitionCounts.removeAll(keepingCapacity: true)
            changeKindCounts.removeAll(keepingCapacity: true)
            flushCount = 0
            lock.unlock()

            let tParts = SubtitleLineCompositor.Transition.allCases.map { "\($0.rawValue)=\(transitions[$0] ?? 0)" }
            let kParts = SubtitleLineChangeKind.allCases.map { "\($0.rawValue)=\(kinds[$0] ?? 0)" }
            NSLog(
                "[OAE.Subtitles] transitions %@ changeKinds %@ uiHzEMA=%.1f flushes=%d",
                tParts.joined(separator: " "),
                kParts.joined(separator: " "),
                ema,
                flushes
            )
            return
        }
        lock.unlock()
    }
}
