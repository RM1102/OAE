import Foundation

/// Semantic kind of a subtitle publish (used for cadence gating and instrumentation).
enum SubtitleLineChangeKind: String, CaseIterable, Equatable {
    case idle
    case confirmUpgrade
    case lineRoll
    case tailRevision
    case reset
}

struct SubtitleLineSnapshot: Equatable {
    struct StyledToken: Equatable {
        let value: String
        let isVolatile: Bool
    }

    /// Single visible caption line (suffix of confirmed + volatile, up to adaptive max words).
    var tokens: [StyledToken]
    /// Index in `tokens` of first volatile token, or `tokens.count` if none.
    var boundaryIndex: Int
    var transition: SubtitleLineCompositor.Transition
    /// Filled by cadence when publishing (compositor leaves `.idle`).
    var changeKind: SubtitleLineChangeKind

    static var empty: SubtitleLineSnapshot {
        .init(tokens: [], boundaryIndex: 0, transition: .reset, changeKind: .idle)
    }
}

struct SubtitleLineCompositor {
    enum Transition: String, CaseIterable {
        case liveFill
        case lineCommitted
        case lineRoll
        case tailRevision
        case confirmationShift
        case reset
    }

    private var previousSessionID: UUID?
    private var previousConfirmed: [String] = []
    private var previousVolatile: [String] = []

    mutating func reset() {
        previousSessionID = nil
        previousConfirmed = []
        previousVolatile = []
    }

    mutating func compose(
        sessionID: UUID,
        confirmed: [String],
        volatile: [String],
        maxVisibleWords: Int
    ) -> SubtitleLineSnapshot {
        let visibleLimit = max(1, min(12, maxVisibleWords))
        let total = confirmed + volatile
        let visibleStart = max(0, total.count - visibleLimit)
        let visible = Array(total.dropFirst(visibleStart))

        guard !visible.isEmpty else {
            let hadContent = !previousConfirmed.isEmpty || !previousVolatile.isEmpty
            previousSessionID = sessionID
            previousConfirmed = []
            previousVolatile = []
            return .init(
                tokens: [],
                boundaryIndex: 0,
                transition: hadContent ? .reset : .liveFill,
                changeKind: .idle
            )
        }

        let transition = classifyTransition(sessionID: sessionID, confirmed: confirmed, volatile: volatile)
        let volatileVisibleCount = min(volatile.count, visible.count)
        let boundary = max(0, visible.count - volatileVisibleCount)
        let styled = visible.enumerated().map { idx, token in
            SubtitleLineSnapshot.StyledToken(value: token, isVolatile: idx >= boundary)
        }

        previousSessionID = sessionID
        previousConfirmed = confirmed
        previousVolatile = volatile

        return .init(
            tokens: styled,
            boundaryIndex: boundary,
            transition: transition,
            changeKind: .idle
        )
    }

    private func classifyTransition(sessionID: UUID, confirmed: [String], volatile: [String]) -> Transition {
        if let prevSession = previousSessionID, prevSession != sessionID {
            return .reset
        }
        if previousConfirmed.isEmpty && previousVolatile.isEmpty {
            return .liveFill
        }
        if confirmed == previousConfirmed && volatile != previousVolatile {
            if volatile.count > previousVolatile.count, Array(volatile.prefix(previousVolatile.count)) == previousVolatile {
                return .liveFill
            }
            return .tailRevision
        }
        if confirmed != previousConfirmed {
            if confirmed.count > previousConfirmed.count,
               Array(confirmed.prefix(previousConfirmed.count)) == previousConfirmed {
                if volatile.count <= previousVolatile.count {
                    return .confirmationShift
                }
                return .lineCommitted
            }
            return .tailRevision
        }
        return .liveFill
    }
}
