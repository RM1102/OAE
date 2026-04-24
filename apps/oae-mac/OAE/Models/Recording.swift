import Foundation

public struct TranscriptSegmentRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var start: Float
    public var end: Float
    public var text: String
    public var confirmed: Bool

    public init(id: UUID = UUID(), start: Float, end: Float, text: String, confirmed: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.confirmed = confirmed
    }
}

public struct Recording: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public var source: Source
    public var finalText: String
    public var language: String?
    public var durationSeconds: Double
    public var postProcessedText: String?

    public enum Source: String, Codable, Sendable { case dictate, capture, file }

    public init(id: UUID = UUID(),
                startedAt: Date = Date(),
                source: Source,
                finalText: String = "",
                language: String? = nil,
                durationSeconds: Double = 0,
                postProcessedText: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.source = source
        self.finalText = finalText
        self.language = language
        self.durationSeconds = durationSeconds
        self.postProcessedText = postProcessedText
    }
}
