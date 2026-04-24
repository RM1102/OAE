import SwiftUI
import AppKit

public struct TranscriptView: View {
    @EnvironmentObject var transcript: TranscriptStore
    public var showTimestamps: Bool
    public init(showTimestamps: Bool = false) { self.showTimestamps = showTimestamps }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(transcript.confirmedSegments) { seg in
                        segmentRow(seg, confirmed: true)
                            .id(seg.id)
                    }
                    if !transcript.partialText.isEmpty {
                        Text(partialPreviewText)
                            .font(.system(size: 15, design: .default))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .id("partial")
                        if shouldShowFinalizingHint {
                            Text("Finalizing…")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if !transcript.postProcessedText.isEmpty {
                        Divider().padding(.vertical, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Post-processed", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(transcript.postProcessedText)
                                .font(.system(size: 15))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            if !transcript.postProcessedLatex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label("Study supplement (inferred — verify on the board)", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.orange)
                                Text(transcript.postProcessedLatex)
                                    .font(.system(size: 14))
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    if transcript.source == .dictate,
                       (!transcript.dictateLiveMathPreview.isEmpty
                        || !transcript.dictateLiveStudyPreview.isEmpty
                        || transcript.dictateLivePostProcessBusy) {
                        Divider().padding(.vertical, 6)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Live background (Ollama)", systemImage: "bolt.horizontal")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            if transcript.dictateLivePostProcessBusy {
                                Text("Updating…")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if !transcript.dictateLiveMathPreview.isEmpty {
                                Text("Recent tail — Unicode")
                                    .font(.caption.weight(.semibold))
                                Text(transcript.dictateLiveMathPreview)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.accentColor.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            if !transcript.dictateLiveStudyPreview.isEmpty {
                                Text("Study batch — inferred")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text(transcript.dictateLiveStudyPreview)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: transcript.partialText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("partial", anchor: .bottom)
                }
            }
            .onChange(of: transcript.confirmedSegments.count) { _, _ in
                if let last = transcript.confirmedSegments.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func segmentRow(_ seg: TranscriptSegmentRow, confirmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if showTimestamps {
                Text(formatTime(seg.start))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .leading)
            }
            Text(seg.text.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 15))
                .foregroundStyle(confirmed ? .primary : .secondary)
                .textSelection(.enabled)
        }
    }

    private func formatTime(_ t: Float) -> String {
        let i = Int(t)
        return String(format: "%02d:%02d", i / 60, i % 60)
    }

    private var partialWordCount: Int {
        transcript.partialText.split(whereSeparator: \.isWhitespace).count
    }

    /// Live dictate partials can be long; showing only a short tail made multi-line speech look “lost”.
    private var partialPreviewText: String {
        transcript.partialText
    }

    private var shouldShowFinalizingHint: Bool {
        partialWordCount > 72
    }
}
