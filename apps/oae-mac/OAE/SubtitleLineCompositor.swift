import Foundation

struct SubtitleLineSnapshot: Equatable {
    struct StyledToken: Equatable {
        let value: String
        let isVolatile: Bool
    }

    var line1: [StyledToken]
    var line2: [StyledToken]
    var boundaryIndex: Int
    var transition: SubtitleLineCompositor.Transition
    var lineBreakChurned: Bool

    static var empty: SubtitleLineSnapshot {
        .init(line1: [], line2: [], boundaryIndex: 0, transition: .reset, lineBreakChurned: false)
    }
}

struct SubtitleLineCompositor {
    enum Transition: String, CaseIterable {
        case bootstrap
        case append
        case tailRevision
        case confirmationShift
        case reset
    }

    private var previousSessionID: UUID?
    private var previousConfirmed: [String] = []
    private var previousVolatile: [String] = []
    private var previousBreakIndex: Int = 0

    mutating func reset() {
        previousSessionID = nil
        previousConfirmed = []
        previousVolatile = []
        previousBreakIndex = 0
    }

    mutating func compose(
        sessionID: UUID,
        confirmed: [String],
        volatile: [String],
        maxVisibleWords: Int
    ) -> SubtitleLineSnapshot {
        let visibleLimit = max(8, maxVisibleWords)
        let total = confirmed + volatile
        let visibleStart = max(0, total.count - visibleLimit)
        let visible = Array(total.dropFirst(visibleStart))

        guard !visible.isEmpty else {
            let hadContent = !previousConfirmed.isEmpty || !previousVolatile.isEmpty
            previousSessionID = sessionID
            previousConfirmed = []
            previousVolatile = []
            previousBreakIndex = 0
            return .init(
                line1: [],
                line2: [],
                boundaryIndex: 0,
                transition: hadContent ? .reset : .bootstrap,
                lineBreakChurned: false
            )
        }

        let transition = classifyTransition(sessionID: sessionID, confirmed: confirmed, volatile: volatile)
        let volatileVisibleCount = min(volatile.count, visible.count)
        let boundary = max(0, visible.count - volatileVisibleCount)
        let breakIndex = stableBreakIndex(totalVisible: visible.count, boundary: boundary, transition: transition)
        let tokens = visible.enumerated().map { idx, token in
            SubtitleLineSnapshot.StyledToken(value: token, isVolatile: idx >= boundary)
        }
        let line1 = Array(tokens.prefix(breakIndex))
        let line2 = Array(tokens.dropFirst(breakIndex))
        let churn = previousBreakIndex != 0 && previousBreakIndex != breakIndex

        previousSessionID = sessionID
        previousConfirmed = confirmed
        previousVolatile = volatile
        previousBreakIndex = breakIndex

        return .init(
            line1: line1,
            line2: line2,
            boundaryIndex: boundary,
            transition: transition,
            lineBreakChurned: churn
        )
    }

    private func classifyTransition(sessionID: UUID, confirmed: [String], volatile: [String]) -> Transition {
        if let prevSession = previousSessionID, prevSession != sessionID {
            return .reset
        }
        if previousConfirmed.isEmpty && previousVolatile.isEmpty {
            return .bootstrap
        }
        if confirmed == previousConfirmed && volatile != previousVolatile {
            if volatile.count > previousVolatile.count, Array(volatile.prefix(previousVolatile.count)) == previousVolatile {
                return .append
            }
            return .tailRevision
        }
        if confirmed != previousConfirmed {
            if confirmed.count > previousConfirmed.count,
               Array(confirmed.prefix(previousConfirmed.count)) == previousConfirmed {
                return .confirmationShift
            }
            return .tailRevision
        }
        if volatile.count > previousVolatile.count {
            return .append
        }
        return .tailRevision
    }

    private func stableBreakIndex(totalVisible: Int, boundary: Int, transition: Transition) -> Int {
        if totalVisible <= 1 { return totalVisible }
        let minLine1 = max(1, totalVisible / 3)
        let maxLine1 = max(minLine1, (totalVisible * 2) / 3)
        let preferred = min(max(totalVisible / 2, minLine1), maxLine1)
        if previousBreakIndex == 0 {
            return preferred
        }

        var candidate = previousBreakIndex
        candidate = min(max(candidate, minLine1), maxLine1)

        switch transition {
        case .tailRevision:
            // Keep the line break stable through volatile churn.
            return candidate
        case .append, .confirmationShift:
            // Hysteresis: move only when previous split drifts too far.
            if abs(candidate - preferred) <= 1 {
                return candidate
            }
            // Keep boundary changes toward the right edge to preserve line 1 anchor.
            if boundary > candidate, boundary - candidate <= 2 {
                return candidate
            }
            return preferred
        case .bootstrap, .reset:
            return preferred
        }
    }
}
