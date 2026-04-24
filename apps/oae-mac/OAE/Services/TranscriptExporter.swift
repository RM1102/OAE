import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt, srt, vtt
    public var id: String { rawValue }
    public var fileExtension: String { rawValue }
    public var displayName: String {
        switch self {
        case .txt: return "Plain text (.txt)"
        case .srt: return "SubRip subtitles (.srt)"
        case .vtt: return "WebVTT (.vtt)"
        }
    }
}

public enum TranscriptExporter {
    public static func render(segments: [TranscriptSegmentRow], fullText: String, format: ExportFormat) -> String {
        switch format {
        case .txt:
            if !fullText.isEmpty { return fullText }
            return segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        case .srt:
            return renderSRT(segments: segments)
        case .vtt:
            return renderVTT(segments: segments)
        }
    }

    private static func renderSRT(segments: [TranscriptSegmentRow]) -> String {
        var out = ""
        for (i, s) in segments.enumerated() {
            out += "\(i + 1)\n"
            out += "\(srtTime(s.start)) --> \(srtTime(s.end))\n"
            out += s.text.trimmingCharacters(in: .whitespaces) + "\n\n"
        }
        return out
    }

    private static func renderVTT(segments: [TranscriptSegmentRow]) -> String {
        var out = "WEBVTT\n\n"
        for s in segments {
            out += "\(vttTime(s.start)) --> \(vttTime(s.end))\n"
            out += s.text.trimmingCharacters(in: .whitespaces) + "\n\n"
        }
        return out
    }

    private static func srtTime(_ secs: Float) -> String {
        let total = Int(secs)
        let ms = Int((secs - Float(total)) * 1000)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
    private static func vttTime(_ secs: Float) -> String {
        let total = Int(secs)
        let ms = Int((secs - Float(total)) * 1000)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
