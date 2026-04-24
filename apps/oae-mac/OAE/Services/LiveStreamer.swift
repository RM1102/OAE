import Foundation
import WhisperKit

/// Thin bridge around WhisperKit's `AudioStreamTranscriber`. It owns the
/// streamer, routes state changes back to the main actor, and exposes a
/// simple `start()` / `stop()` API for the Dictate tab.
@MainActor
public final class LiveStreamer {
    public enum StreamingPreset: String, CaseIterable, Identifiable {
        case ultraLowLatency
        case balanced

        public var id: String { rawValue }
        var displayName: String {
            switch self {
            case .ultraLowLatency: return "Ultra Low Lag"
            case .balanced: return "Balanced"
            }
        }
    }

    public struct EventTimestamp: Sendable {
        public let emittedAt: Date
        public init(emittedAt: Date) {
            self.emittedAt = emittedAt
        }
    }

    private var transcriber: AudioStreamTranscriber?
    private let engine = TranscriptionEngine.shared

    public init() {}

    public var isRunning: Bool { transcriber != nil }

    public func start(language: String?, requiredSegmentsForConfirmation: Int, preset: StreamingPreset,
                      onState: @escaping @MainActor (AudioStreamTranscriber.State, EventTimestamp) -> Void) async throws {
        guard let wk = engine.whisperKit else {
            throw EngineError.modelNotLoaded("WhisperKit not loaded yet")
        }
        guard let tokenizer = wk.tokenizer else {
            throw EngineError.modelNotLoaded("tokenizer missing")
        }

        // Keep worker scheduling modest for smoother low-latency updates.
        let workers: Int = {
            switch preset {
            case .ultraLowLatency:
                return max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
            case .balanced:
                return max(3, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))
            }
        }()
        let silenceThreshold: Float = preset == .ultraLowLatency ? 0.1 : 0.14
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            concurrentWorkerCount: workers,
            chunkingStrategy: .vad
        )

        let transcriber = AudioStreamTranscriber(
            audioEncoder: wk.audioEncoder,
            featureExtractor: wk.featureExtractor,
            segmentSeeker: wk.segmentSeeker,
            textDecoder: wk.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: wk.audioProcessor,
            decodingOptions: options,
            requiredSegmentsForConfirmation: requiredSegmentsForConfirmation,
            // Streaming preset controls endpointing aggressiveness.
            silenceThreshold: silenceThreshold,
            compressionCheckWindow: 60,
            useVAD: true,
            stateChangeCallback: { _, newState in
                let timestamp = EventTimestamp(emittedAt: Date())
                Task { @MainActor in onState(newState, timestamp) }
            }
        )
        self.transcriber = transcriber
        try await transcriber.startStreamTranscription()
    }

    public func stop() async {
        guard let t = transcriber else { return }
        await t.stopStreamTranscription()
        transcriber = nil
    }
}
