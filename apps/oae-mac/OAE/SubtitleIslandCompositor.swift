import Foundation

/// Maps engine **confirmed** vs **volatile** word streams into exactly `N` single-line cells (left = confirmed tail, right = volatile tail).
struct SubtitleIslandCompositor {
    enum Transition: String, CaseIterable {
        case bootstrap
        case append
        case tailRevision
        case confirmationShift
        case reset
    }

    private var prevSessionID: UUID?
    private var prevC: [String] = []
    private var prevV: [String] = []
    private var hadAnyContent = false

    mutating func compose(
        capacity rawCapacity: Int,
        sessionID: UUID,
        confirmed C: [String],
        volatile V: [String],
        instrument: SubtitleIslandInstrumentation?
    ) -> (slots: [String], transition: Transition) {
        let N = max(4, rawCapacity)
        let empty = Array(repeating: "", count: N)

        if prevSessionID != nil, sessionID != prevSessionID {
            prevC = []
            prevV = []
            hadAnyContent = false
        }

        guard !C.isEmpty || !V.isEmpty else {
            let had = hadAnyContent
            prevSessionID = sessionID
            prevC = []
            prevV = []
            hadAnyContent = false
            if had {
                instrument?.record(.reset)
            }
            return (empty, had ? .reset : .reset)
        }

        let slots = Self.buildSlots(N: N, C: C, V: V)
        let transition = classify(C: C, V: V, sessionID: sessionID)
        let unchanged = C == prevC && V == prevV && sessionID == prevSessionID && hadAnyContent

        prevSessionID = sessionID
        prevC = C
        prevV = V
        hadAnyContent = true

        if !unchanged {
            instrument?.record(transition)
        }
        return (slots, transition)
    }

    mutating func reset() {
        prevSessionID = nil
        prevC = []
        prevV = []
        hadAnyContent = false
    }

    private mutating func classify(C: [String], V: [String], sessionID: UUID) -> Transition {
        if !hadAnyContent {
            return .bootstrap
        }

        if C == prevC && V == prevV {
            return .tailRevision
        }

        if C == prevC, V != prevV {
            if V.count > prevV.count, prevV.count <= V.count {
                let prefix = Array(V.prefix(prevV.count))
                if prefix == prevV {
                    return .append
                }
            }
            return .tailRevision
        }

        if C != prevC {
            if C.count > prevC.count, prevC.count <= C.count {
                let prefix = Array(C.prefix(prevC.count))
                if prefix == prevC {
                    return .confirmationShift
                }
            }
            if C.count == prevC.count, V == prevV {
                return .tailRevision
            }
            if V == prevV {
                return .confirmationShift
            }
            return .tailRevision
        }

        return .append
    }

    private static func buildSlots(N: Int, C: [String], V: [String]) -> [String] {
        var slots = Array(repeating: "", count: N)
        let volatileSlotCount: Int = V.isEmpty ? 0 : min(N, max(1, V.count))
        let confirmedSlotCount = N - volatileSlotCount
        let cTail = Array(C.suffix(confirmedSlotCount))
        let cOffset = confirmedSlotCount - cTail.count
        for (i, w) in cTail.enumerated() where cOffset + i < N {
            slots[cOffset + i] = w
        }
        let vTail = Array(V.suffix(volatileSlotCount))
        let vStart = confirmedSlotCount
        for (i, w) in vTail.enumerated() where vStart + i < N {
            slots[vStart + i] = w
        }
        return slots
    }
}
