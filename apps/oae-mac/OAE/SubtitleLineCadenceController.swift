import Combine
import Foundation

@MainActor
final class SubtitleLineCadenceController: ObservableObject {
    @Published private(set) var snapshot: SubtitleLineSnapshot = .empty

    private weak var transcript: TranscriptStore?
    private var compositor = SubtitleLineCompositor()
    private var cadenceTick: AnyCancellable?

    /// Upper bound for adaptive window (typically 7; burst allows 8).
    private var maxVisibleWordsCap: Int = 7
    private var pendingInput: (sessionID: UUID, confirmed: [String], volatile: [String], source: Recording.Source)?
    private var hasPending: Bool = false
    private var lastAcceptedAt: CFAbsoluteTime = 0
    private var lastVolatilePublishAt: CFAbsoluteTime = 0
    private var lastTailRewriteAt: CFAbsoluteTime = 0
    private var lineCommitHoldUntil: CFAbsoluteTime = 0
    private var previousAcceptedSessionID: UUID?
    private var previousAcceptedConfirmed: [String] = []
    private var previousAcceptedVolatile: [String] = []
    /// Tracks volatile indices that have already consumed their one allowed rewrite.
    private var volatileRewriteConsumedIndices: Set<Int> = []

    private var debounceSeconds: CFAbsoluteTime = 0.07
    private var volatileThrottleSeconds: CFAbsoluteTime = 0.14
    private var tailRewriteCooldownSeconds: CFAbsoluteTime = 0.32
    private var lineCommitHoldSeconds: CFAbsoluteTime = 0.30
    /// Minimum time between switching publish kinds (confirm vs roll family) for readability.
    private var interChangeLagSeconds: CFAbsoluteTime = 0.28
    private let instrumentation = SubtitleIslandInstrumentation.shared

    // Adaptive 7/8 + inter-change gate
    private var volatileBurstTimestamps: [CFAbsoluteTime] = []
    /// Last volatile word count seen on any flush tick (tracks growth for burst detection).
    private var volatileCountLastObserved: Int = 0
    private var lastPublishedChangeKind: SubtitleLineChangeKind = .idle
    private var interChangeAllowedAfter: CFAbsoluteTime = 0

    func start(transcript: TranscriptStore, maxVisibleWords: Int, paceMode: SubtitlePaceMode) {
        stop()
        self.transcript = transcript
        self.maxVisibleWordsCap = max(7, min(8, maxVisibleWords))
        applyPaceMode(paceMode)
        compositor.reset()
        snapshot = .empty
        lastPublishedChangeKind = .idle
        interChangeAllowedAfter = 0
        volatileBurstTimestamps.removeAll()
        volatileCountLastObserved = 0
        capturePending()

        cadenceTick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.flush()
            }
    }

    func stop() {
        cadenceTick?.cancel()
        cadenceTick = nil
        transcript = nil
        hasPending = false
        previousAcceptedSessionID = nil
        previousAcceptedConfirmed = []
        previousAcceptedVolatile = []
        volatileRewriteConsumedIndices = []
        lastVolatilePublishAt = 0
        lastTailRewriteAt = 0
        lineCommitHoldUntil = 0
        volatileBurstTimestamps.removeAll()
        volatileCountLastObserved = 0
        lastPublishedChangeKind = .idle
        interChangeAllowedAfter = 0
    }

    func updateWindowSize(_ words: Int) {
        maxVisibleWordsCap = max(7, min(8, words))
        compositor.reset()
        capturePending()
        flush(force: true)
    }

    func updatePaceMode(_ paceMode: SubtitlePaceMode) {
        applyPaceMode(paceMode)
    }

    func capturePending() {
        guard let transcript else { return }
        pendingInput = (
            sessionID: transcript.subtitleFeedDictateSessionID,
            confirmed: transcript.source == .dictate ? transcript.subtitleConfirmedWords : [],
            volatile: transcript.source == .dictate ? transcript.subtitleVolatileWords : [],
            source: transcript.source
        )
        hasPending = true
    }

    private func flush(force: Bool = false) {
        guard hasPending, let pending = pendingInput else { return }
        if !force && shouldHoldForDebounce(pending: pending) { return }

        let normalized = normalizeWithOneRewriteLimit(pending: pending)
        let now = CFAbsoluteTimeGetCurrent()
        if !force && now < lineCommitHoldUntil {
            return
        }

        if previousAcceptedSessionID != normalized.sessionID {
            volatileBurstTimestamps.removeAll()
            volatileCountLastObserved = normalized.volatile.count
        }

        let vCount = normalized.volatile.count
        if vCount > volatileCountLastObserved {
            volatileBurstTimestamps.append(now)
        }
        volatileCountLastObserved = vCount

        let adaptiveLimit = adaptiveVisibleLimit(at: now)
        let ideal = compositor.compose(
            sessionID: normalized.sessionID,
            confirmed: normalized.confirmed,
            volatile: normalized.volatile,
            maxVisibleWords: adaptiveLimit
        )

        if !force, shouldSkipByCadence(snapshot: ideal, now: now) {
            return
        }

        let kind = inferChangeKind(published: snapshot, ideal: ideal)
        if kind == .idle {
            if sameVisual(ideal, snapshot) {
                hasPending = false
            }
            return
        }

        if !force, shouldDeferInterChange(kind: kind, now: now) {
            return
        }

        var published = ideal
        published.changeKind = kind

        hasPending = false
        snapshot = published
        instrumentation.record(snapshot: published)
        instrumentation.recordFlush()
        lastAcceptedAt = now
        lastPublishedChangeKind = kind
        interChangeAllowedAfter = now + interChangeLagSeconds
        if kind == .reset {
            lastPublishedChangeKind = .idle
            interChangeAllowedAfter = 0
        }

        if ideal.transition == .tailRevision {
            lastTailRewriteAt = now
        }
        if ideal.transition == .lineCommitted || ideal.transition == .confirmationShift || ideal.transition == .lineRoll {
            lineCommitHoldUntil = now + lineCommitHoldSeconds
        }
        if ideal.transition == .liveFill {
            lastVolatilePublishAt = now
        }
        previousAcceptedSessionID = normalized.sessionID
        previousAcceptedConfirmed = normalized.confirmed
        previousAcceptedVolatile = normalized.volatile
    }

    private func sameVisual(_ a: SubtitleLineSnapshot, _ b: SubtitleLineSnapshot) -> Bool {
        a.tokens == b.tokens && a.boundaryIndex == b.boundaryIndex && a.transition == b.transition
    }

    private func adaptiveVisibleLimit(at now: CFAbsoluteTime) -> Int {
        let window: CFAbsoluteTime = 0.45
        volatileBurstTimestamps.removeAll { now - $0 > window }
        let burst = volatileBurstTimestamps.count
        let base = 7
        let boosted = burst >= 3 ? 8 : base
        return min(maxVisibleWordsCap, max(base, min(8, boosted)))
    }

    /// Buckets for inter-change lag: confirm-style vs roll-style must not publish back-to-back within `interChangeLagSeconds`.
    private func rollFamily(_ k: SubtitleLineChangeKind) -> Bool {
        switch k {
        case .lineRoll, .tailRevision: return true
        default: return false
        }
    }

    private func shouldDeferInterChange(kind: SubtitleLineChangeKind, now: CFAbsoluteTime) -> Bool {
        guard kind != .reset && kind != .idle else { return false }
        let prev = lastPublishedChangeKind
        guard prev != .idle else { return false }
        let switchingConfirmVsRoll =
            (prev == .confirmUpgrade && rollFamily(kind))
            || (rollFamily(prev) && kind == .confirmUpgrade)
        guard switchingConfirmVsRoll else { return false }
        return now < interChangeAllowedAfter
    }

    private func inferChangeKind(published: SubtitleLineSnapshot, ideal: SubtitleLineSnapshot) -> SubtitleLineChangeKind {
        let pv = published.tokens.map(\.value)
        let iv = ideal.tokens.map(\.value)

        if ideal.tokens.isEmpty && published.tokens.isEmpty {
            return ideal.transition == .reset ? .reset : .idle
        }
        if published.tokens.isEmpty && !ideal.tokens.isEmpty { return .lineRoll }
        if !published.tokens.isEmpty && ideal.tokens.isEmpty { return .reset }
        if ideal.transition == .reset { return .reset }

        if pv == iv {
            let upgraded = zip(published.tokens, ideal.tokens).contains { $0.isVolatile && !$1.isVolatile }
            return upgraded ? .confirmUpgrade : .idle
        }
        if ideal.transition == .tailRevision { return .tailRevision }
        return .lineRoll
    }

    private func shouldHoldForDebounce(pending: (sessionID: UUID, confirmed: [String], volatile: [String], source: Recording.Source)) -> Bool {
        if pending.source != .dictate { return false }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastAcceptedAt >= debounceSeconds { return false }

        let previous = snapshot
        let prevTokens = previous.tokens.map(\.value)
        let newTokens = pending.confirmed + pending.volatile
        if prevTokens.isEmpty || newTokens.isEmpty { return false }

        let shared = min(prevTokens.count, newTokens.count)
        if shared <= 1 { return false }
        let samePrefix = zip(prevTokens.prefix(shared - 1), newTokens.prefix(shared - 1)).allSatisfy(==)
        let onlyTailChanged = samePrefix && prevTokens.last != newTokens.last
        return onlyTailChanged
    }

    private func shouldSkipByCadence(snapshot: SubtitleLineSnapshot, now: CFAbsoluteTime) -> Bool {
        switch snapshot.transition {
        case .liveFill:
            return (now - lastVolatilePublishAt) < volatileThrottleSeconds
        case .tailRevision:
            return (now - lastTailRewriteAt) < tailRewriteCooldownSeconds
        case .lineCommitted, .lineRoll, .confirmationShift, .reset:
            return false
        }
    }

    /// Hard limiter: if confirmed lane is stable and volatile length is stable, each volatile
    /// index can be rewritten at most once. Further rewrites at the same index are ignored.
    private func normalizeWithOneRewriteLimit(
        pending: (sessionID: UUID, confirmed: [String], volatile: [String], source: Recording.Source)
    ) -> (sessionID: UUID, confirmed: [String], volatile: [String], source: Recording.Source) {
        guard pending.source == .dictate else {
            volatileRewriteConsumedIndices = []
            return pending
        }
        if previousAcceptedSessionID != pending.sessionID {
            volatileRewriteConsumedIndices = []
            return pending
        }

        guard pending.confirmed == previousAcceptedConfirmed else {
            volatileRewriteConsumedIndices = []
            return pending
        }

        guard pending.volatile.count == previousAcceptedVolatile.count else {
            volatileRewriteConsumedIndices = []
            return pending
        }

        var adjustedVolatile = pending.volatile
        let fillerWords: Set<String> = [
            "uh", "um", "hmm", "mm", "ah", "oh", "like", "you", "know"
        ]
        for i in adjustedVolatile.indices {
            guard adjustedVolatile[i] != previousAcceptedVolatile[i] else { continue }
            let oldLower = previousAcceptedVolatile[i].lowercased()
            let newLower = adjustedVolatile[i].lowercased()
            if fillerWords.contains(oldLower) && fillerWords.contains(newLower) {
                adjustedVolatile[i] = previousAcceptedVolatile[i]
                continue
            }
            if volatileRewriteConsumedIndices.contains(i) {
                adjustedVolatile[i] = previousAcceptedVolatile[i]
            } else {
                volatileRewriteConsumedIndices.insert(i)
            }
        }

        return (
            sessionID: pending.sessionID,
            confirmed: pending.confirmed,
            volatile: adjustedVolatile,
            source: pending.source
        )
    }

    private func applyPaceMode(_ paceMode: SubtitlePaceMode) {
        switch paceMode {
        case .lectureStable:
            debounceSeconds = 0.08
            volatileThrottleSeconds = 0.14
            tailRewriteCooldownSeconds = 0.34
            lineCommitHoldSeconds = 0.30
            interChangeLagSeconds = 0.30
        case .realtimeFaster:
            debounceSeconds = 0.05
            volatileThrottleSeconds = 0.10
            tailRewriteCooldownSeconds = 0.20
            lineCommitHoldSeconds = 0.18
            interChangeLagSeconds = 0.22
        }
    }
}
