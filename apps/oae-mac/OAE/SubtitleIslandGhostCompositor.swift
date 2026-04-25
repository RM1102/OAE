import Foundation
import SwiftUI

/// Keeps a dim “ghost” copy of words Whisper temporarily drops from the live tail so the
/// subtitle island does not collapse and reflow every time LocalAgreement rewrites.
struct SubtitleIslandGhostCompositor {
    private(set) var solidWords: [String] = []
    private(set) var ghostWords: [String] = []

    private let maxGhostWords: Int

    init(maxGhostWords: Int = 28) {
        self.maxGhostWords = maxGhostWords
    }

    var hasGhost: Bool { !ghostWords.isEmpty }

    mutating func reset() {
        solidWords = []
        ghostWords = []
    }

    /// Feed the latest canonical suffix window (from `TranscriptStore.fullText`).
    mutating func consume(canonicalWindow: [String]) -> AttributedString {
        let new = canonicalWindow
        if new.isEmpty {
            solidWords = []
            ghostWords = []
            return Self.placeholder
        }

        let prev = solidWords + ghostWords

        // Tail removed but prefix unchanged → keep removed tail as ghost (layout stays wide).
        if !prev.isEmpty, new.count < prev.count, new == Array(prev.prefix(new.count)) {
            solidWords = new
            let dropped = Array(prev.suffix(prev.count - new.count))
            ghostWords = Array(dropped.suffix(maxGhostWords))
            return Self.render(solid: solidWords, ghost: ghostWords)
        }

        // Growing again: new extends solid and matches ghost prefix → consume ghost into solid.
        if !ghostWords.isEmpty, new.count > solidWords.count,
           Array(new.prefix(solidWords.count)) == solidWords {
            let added = Array(new.dropFirst(solidWords.count))
            if !added.isEmpty, added.count <= ghostWords.count,
               added == Array(ghostWords.prefix(added.count)) {
                solidWords = new
                ghostWords = Array(ghostWords.dropFirst(added.count))
                return Self.render(solid: solidWords, ghost: ghostWords)
            }
            if !prev.isEmpty, new.count >= prev.count,
               Array(new.prefix(prev.count)) == prev {
                solidWords = new
                ghostWords = []
                return Self.render(solid: solidWords, ghost: ghostWords)
            }
            solidWords = new
            ghostWords = []
            return Self.render(solid: solidWords, ghost: ghostWords)
        }

        solidWords = new
        ghostWords = []
        return Self.render(solid: solidWords, ghost: ghostWords)
    }

    /// Drop dim tail after a timeout so stale ghosts never stick forever.
    mutating func expireGhostIfNeeded(canonicalWindow: [String]) -> AttributedString {
        guard !ghostWords.isEmpty else {
            return Self.render(solid: solidWords, ghost: ghostWords)
        }
        solidWords = canonicalWindow
        ghostWords = []
        return Self.render(solid: solidWords, ghost: ghostWords)
    }

    private static var placeholder: AttributedString {
        var a = AttributedString("Your live subtitles will appear here...")
        a.foregroundColor = .white.opacity(0.55)
        return a
    }

    private static func render(solid: [String], ghost: [String]) -> AttributedString {
        if solid.isEmpty, ghost.isEmpty { return placeholder }
        var out = AttributedString()
        if !solid.isEmpty {
            var s = AttributedString(solid.joined(separator: " "))
            s.foregroundColor = .white
            out.append(s)
        }
        if !ghost.isEmpty {
            if !out.characters.isEmpty {
                var sp = AttributedString(" ")
                sp.foregroundColor = .white.opacity(0.35)
                out.append(sp)
            }
            var g = AttributedString(ghost.joined(separator: " "))
            g.foregroundColor = .white.opacity(0.42)
            out.append(g)
        }
        return out
    }
}
