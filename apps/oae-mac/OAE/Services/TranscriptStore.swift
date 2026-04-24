import Foundation
import Combine

/// Single source of truth for the transcript currently visible in the UI.
/// Views read this; the streaming engine and post-processor both write to it.
@MainActor
public final class TranscriptStore: ObservableObject {
    public static let shared = TranscriptStore()

    @Published public var confirmedSegments: [TranscriptSegmentRow] = []
    @Published public var partialText: String = ""
    @Published public var postProcessedText: String = ""
    @Published public var postProcessedLatex: String = ""
    @Published public var isPostProcessing: Bool = false
    @Published public var source: Recording.Source = .dictate
    @Published public private(set) var activeSessionID: UUID = UUID()
    /// Latest live Unicode pass on a recent tail (Dictate only; does not replace ASR segments).
    @Published public private(set) var dictateLiveMathPreview: String = ""
    /// Latest live study batch from a longer window (Dictate only; inferred — verify on board).
    @Published public private(set) var dictateLiveStudyPreview: String = ""
    @Published public private(set) var dictateLivePostProcessBusy: Bool = false

    private var dictateLiveBackgroundDepth: Int = 0

    private struct SourceBucket {
        var confirmedSegments: [TranscriptSegmentRow] = []
        var partialText: String = ""
        var postProcessedText: String = ""
        var postProcessedLatex: String = ""
        var dictateLiveMathPreview: String = ""
        var dictateLiveStudyPreview: String = ""
    }

    private var buckets: [Recording.Source: SourceBucket] = [
        .dictate: SourceBucket(),
        .capture: SourceBucket(),
        .file: SourceBucket()
    ]
    private var sessionIDs: [Recording.Source: UUID] = [
        .dictate: UUID(),
        .capture: UUID(),
        .file: UUID()
    ]

    private init() {}

    public var confirmedText: String {
        confirmedSegments.map { $0.text.trimmingCharacters(in: .whitespaces) }
                         .joined(separator: " ")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var fullText: String {
        let p = partialText.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return confirmedText }
        return [confirmedText, p].joined(separator: " ")
    }

    public func activate(source: Recording.Source) {
        self.source = source
        activeSessionID = sessionIDs[source] ?? UUID()
        loadPublishedState(from: source)
    }

    public func reset(source: Recording.Source) {
        let session = UUID()
        sessionIDs[source] = session
        activeSessionID = session
        buckets[source] = SourceBucket()
        if source == .dictate {
            dictateLiveBackgroundDepth = 0
            dictateLivePostProcessBusy = false
        }
        activate(source: source)
        isPostProcessing = false
    }

    /// Start a new guarded session for the specified source and clear prior output.
    @discardableResult
    public func beginSession(source: Recording.Source) -> UUID {
        reset(source: source)
        return activeSessionID
    }

    public func replaceConfirmed(with segments: [TranscriptSegmentRow]) {
        mutateBucket(for: source) { bucket in
            bucket.confirmedSegments = segments
            bucket.partialText = ""
        }
    }

    public func appendConfirmed(_ rows: [TranscriptSegmentRow]) {
        mutateBucket(for: source) { bucket in
            for r in rows where !bucket.confirmedSegments.contains(r) {
                bucket.confirmedSegments.append(r)
            }
        }
    }

    /// Guarded Dictate mutation to prevent stale/background updates from other sessions.
    public func applyDictateUpdate(sessionID: UUID, confirmedRows: [TranscriptSegmentRow], partial: String, rewriteLookbackWords: Int = 10) {
        guard sessionID == sessionIDs[.dictate] else { return }
        mutateBucket(for: .dictate) { bucket in
            let oldWords = bucket.confirmedSegments
                .flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
            let newWords = confirmedRows
                .flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
            let mergedWords = stabilizedWords(old: oldWords, new: newWords, rewriteLookbackWords: rewriteLookbackWords)
            let mergedText = mergedWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            bucket.confirmedSegments = mergedText.isEmpty
                ? []
                : [TranscriptSegmentRow(start: 0, end: 0, text: mergedText, confirmed: true)]
            bucket.partialText = partial
        }
    }

    /// Guarded Capture finalization to prevent cross-mode transcript bleed.
    public func applyCaptureFinal(sessionID: UUID, rows: [TranscriptSegmentRow]) {
        guard sessionID == sessionIDs[.capture] else { return }
        mutateBucket(for: .capture) { bucket in
            bucket.confirmedSegments = rows
            bucket.partialText = ""
        }
    }

    public func updateFilePartial(_ text: String) {
        mutateBucket(for: .file) { bucket in
            bucket.partialText = text
        }
    }

    public func applyPostProcessedUnicode(_ unicodeText: String, latex: String = "") {
        let cleaned = unicodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        mutateBucket(for: source) { bucket in
            bucket.confirmedSegments = [TranscriptSegmentRow(start: 0, end: 0, text: cleaned, confirmed: true)]
            bucket.partialText = ""
            bucket.postProcessedText = cleaned
            bucket.postProcessedLatex = latex
        }
    }

    public func setPostProcessedText(_ text: String) {
        mutateBucket(for: source) { bucket in
            bucket.postProcessedText = text
        }
    }

    public func setPostProcessedLatex(_ text: String) {
        mutateBucket(for: source) { bucket in
            bucket.postProcessedLatex = text
        }
    }

    public func updateDictateLivePostProcessPreviews(math: String?, study: String?) {
        mutateBucket(for: .dictate) { bucket in
            if let m = math { bucket.dictateLiveMathPreview = m }
            if let s = study { bucket.dictateLiveStudyPreview = s }
        }
    }

    public func clearDictateLivePostProcessPreviews() {
        dictateLiveBackgroundDepth = 0
        dictateLivePostProcessBusy = false
        mutateBucket(for: .dictate) { bucket in
            bucket.dictateLiveMathPreview = ""
            bucket.dictateLiveStudyPreview = ""
        }
    }

    public func beginDictateLiveBackgroundWork() {
        dictateLiveBackgroundDepth += 1
        dictateLivePostProcessBusy = true
    }

    public func endDictateLiveBackgroundWork() {
        dictateLiveBackgroundDepth = max(0, dictateLiveBackgroundDepth - 1)
        dictateLivePostProcessBusy = dictateLiveBackgroundDepth > 0
    }

    private func mutateBucket(for source: Recording.Source, _ update: (inout SourceBucket) -> Void) {
        var bucket = buckets[source] ?? SourceBucket()
        update(&bucket)
        buckets[source] = bucket
        if source == .dictate {
            let d = buckets[.dictate] ?? SourceBucket()
            dictateLiveMathPreview = d.dictateLiveMathPreview
            dictateLiveStudyPreview = d.dictateLiveStudyPreview
        }
        if self.source == source {
            loadPublishedState(from: source)
        }
    }

    private func loadPublishedState(from source: Recording.Source) {
        let bucket = buckets[source] ?? SourceBucket()
        confirmedSegments = bucket.confirmedSegments
        partialText = bucket.partialText
        postProcessedText = bucket.postProcessedText
        postProcessedLatex = bucket.postProcessedLatex
        let dictateBucket = buckets[.dictate] ?? SourceBucket()
        dictateLiveMathPreview = dictateBucket.dictateLiveMathPreview
        dictateLiveStudyPreview = dictateBucket.dictateLiveStudyPreview
    }

    private func stabilizedWords(old: [String], new: [String], rewriteLookbackWords: Int) -> [String] {
        guard !old.isEmpty else { return new }
        let lookback = max(1, rewriteLookbackWords)
        let immutableCount = max(0, old.count - lookback)
        let frozenPrefix = Array(old.prefix(immutableCount))
        let suffixFromNew = new.count > immutableCount ? Array(new.dropFirst(immutableCount)) : []
        if suffixFromNew.isEmpty {
            return frozenPrefix
        }
        return frozenPrefix + suffixFromNew
    }
}
