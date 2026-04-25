import Foundation

/// Fixed-capacity subtitle window: exactly **N** word slots (leading cells may be `""`).
/// - **FIFO:** when the global word count increases and the new canonical tail is the previous
///   tail shifted left by `d` with `d` new words on the right, we assign slot-by-slot from the
///   new tail (same numbers as `slots[i] = target[i]`, but we only take this path when the shift
///   identity holds so we do not repack on pure rewrites).
/// - **Rewrites:** when the word count does not increase (or shift pattern fails), update only the
///   prefix before the longest common **suffix** with the previous row so stable trailing words
///   stay put slot-wise.
///
/// Without ASR “rewrite” events this remains heuristic; rare full resets are acceptable.
struct SubtitleIslandRingViewport {
    let capacity: Int

    private(set) var slots: [String]
    private var lastAllWordsCount: Int

    init(capacity: Int) {
        self.capacity = max(4, capacity)
        self.slots = Array(repeating: "", count: self.capacity)
        self.lastAllWordsCount = 0
    }

    mutating func reset() {
        slots = Array(repeating: "", count: capacity)
        lastAllWordsCount = 0
    }

    /// Last `min(capacity, allWords.count)` words, left-padded with `""` to `capacity`.
    private func canonicalRow(allWords: [String]) -> [String] {
        let m = min(capacity, allWords.count)
        let tail = m > 0 ? Array(allWords.suffix(m)) : [String]()
        var row = Array(repeating: "", count: capacity)
        let start = capacity - tail.count
        for i in tail.indices {
            row[start + i] = tail[i]
        }
        return row
    }

    /// Largest `k` with `a.suffix(k) == b.suffix(k)` element-wise (`a`, `b` same length).
    private static func longestCommonWordSuffix(_ a: [String], _ b: [String]) -> Int {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let n = a.count
        var k = 0
        while k < n {
            if a[n - 1 - k] != b[n - 1 - k] { break }
            k += 1
        }
        return k
    }

    mutating func apply(allWords: [String]) -> [String] {
        if allWords.isEmpty {
            reset()
            return slots
        }

        let target = canonicalRow(allWords: allWords)
        let added = allWords.count - lastAllWordsCount

        if lastAllWordsCount == 0 || slots.allSatisfy({ $0.isEmpty }) {
            slots = target
            lastAllWordsCount = allWords.count
            return slots
        }

        // New tokens appended: canonical tail is authoritative (FIFO is implicit in suffix(N)).
        if added > 0 {
            slots = target
            lastAllWordsCount = allWords.count
            return slots
        }

        // Rewrite / delete / same length: only patch the unstable prefix so the shared suffix
        // stays slot-aligned (reduces “everything jumped left” when only early tail words change).
        let k = Self.longestCommonWordSuffix(slots, target)
        for i in 0..<(capacity - k) {
            slots[i] = target[i]
        }
        lastAllWordsCount = allWords.count
        return slots
    }
}
