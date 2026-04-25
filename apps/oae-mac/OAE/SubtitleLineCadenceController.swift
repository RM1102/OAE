import Combine
import Foundation

@MainActor
final class SubtitleLineCadenceController: ObservableObject {
    @Published private(set) var snapshot: SubtitleLineSnapshot = .empty

    private weak var transcript: TranscriptStore?
    private var compositor = SubtitleLineCompositor()
    private var cadenceTick: AnyCancellable?

    private var maxVisibleWords: Int = 15
    private var pendingInput: (sessionID: UUID, confirmed: [String], volatile: [String], source: Recording.Source)?
    private var hasPending: Bool = false
    private var lastAcceptedAt: CFAbsoluteTime = 0
    private var previousAcceptedSessionID: UUID?
    private var previousAcceptedConfirmed: [String] = []
    private var previousAcceptedVolatile: [String] = []
    /// Tracks volatile indices that have already consumed their one allowed rewrite.
    private var volatileRewriteConsumedIndices: Set<Int> = []

    private let debounceSeconds: CFAbsoluteTime = 0.07
    private let instrumentation = SubtitleIslandInstrumentation.shared

    func start(transcript: TranscriptStore, maxVisibleWords: Int) {
        stop()
        self.transcript = transcript
        self.maxVisibleWords = max(8, maxVisibleWords)
        compositor.reset()
        snapshot = .empty
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
    }

    func updateWindowSize(_ words: Int) {
        maxVisibleWords = max(8, words)
        compositor.reset()
        capturePending()
        flush(force: true)
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
        hasPending = false
        let newSnapshot = compositor.compose(
            sessionID: normalized.sessionID,
            confirmed: normalized.confirmed,
            volatile: normalized.volatile,
            maxVisibleWords: maxVisibleWords
        )
        snapshot = newSnapshot
        instrumentation.record(snapshot: newSnapshot)
        instrumentation.recordFlush()
        lastAcceptedAt = CFAbsoluteTimeGetCurrent()
        previousAcceptedSessionID = normalized.sessionID
        previousAcceptedConfirmed = normalized.confirmed
        previousAcceptedVolatile = normalized.volatile
    }

    private func shouldHoldForDebounce(pending: (sessionID: UUID, confirmed: [String], volatile: [String], source: Recording.Source)) -> Bool {
        if pending.source != .dictate { return false }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastAcceptedAt >= debounceSeconds { return false }

        // Hysteresis: if confirmed lane is unchanged and only the final volatile token churns,
        // wait one more debounce window to avoid high-frequency micro-jitter.
        let previous = snapshot
        let prevTokens = (previous.line1 + previous.line2).map(\.value)
        let newTokens = pending.confirmed + pending.volatile
        if prevTokens.isEmpty || newTokens.isEmpty { return false }

        let shared = min(prevTokens.count, newTokens.count)
        if shared <= 1 { return false }
        let samePrefix = zip(prevTokens.prefix(shared - 1), newTokens.prefix(shared - 1)).allSatisfy(==)
        let onlyTailChanged = samePrefix && prevTokens.last != newTokens.last
        return onlyTailChanged
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

        // Confirmation boundary moved: reset volatile rewrite budget.
        guard pending.confirmed == previousAcceptedConfirmed else {
            volatileRewriteConsumedIndices = []
            return pending
        }

        // Window changed (append/delete): treat as new volatile span and reset per-index budget.
        guard pending.volatile.count == previousAcceptedVolatile.count else {
            volatileRewriteConsumedIndices = []
            return pending
        }

        var adjustedVolatile = pending.volatile
        for i in adjustedVolatile.indices {
            guard adjustedVolatile[i] != previousAcceptedVolatile[i] else { continue }
            if volatileRewriteConsumedIndices.contains(i) {
                // Reject repeat rewrite at this index; keep last accepted value.
                adjustedVolatile[i] = previousAcceptedVolatile[i]
            } else {
                // Allow exactly one rewrite at this index.
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
}
