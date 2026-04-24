import Foundation
import SwiftUI
import Combine

/// Owns push-to-talk capture state so switching away from the Capture tab does not tear down
/// `AudioCapture` or drop an in-progress recording before transcribe.
@MainActor
public final class CaptureSessionController: ObservableObject {
    public let capture = AudioCapture()
    @Published public private(set) var isTranscribing = false
    @Published public var errorText: String?

    private var timer: AnyCancellable?
    private var recordingStart: Date?
    @Published public private(set) var elapsed: TimeInterval = 0
    private var captureSessionID = UUID()

    public init() {}

    public var statusLine: String {
        if isTranscribing { return "Transcribing…" }
        if capture.isRecording {
            return String(format: "Recording · %02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
        }
        return "Ready"
    }

    public func startRecording(transcript: TranscriptStore) {
        guard !capture.isRecording && !isTranscribing else { return }
        errorText = nil
        captureSessionID = transcript.beginSession(source: .capture)
        Task { @MainActor in
            do {
                try await self.capture.start()
                recordingStart = Date()
                elapsed = 0
                timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
                    .sink { [weak self] _ in
                        guard let self, let s = self.recordingStart else { return }
                        self.elapsed = Date().timeIntervalSince(s)
                    }
            } catch {
                self.errorText = error.localizedDescription
            }
        }
    }

    public func stopAndTranscribe(engine: TranscriptionEngine, transcript: TranscriptStore) {
        guard capture.isRecording else { return }
        let samples = capture.snapshotSamples()
        capture.stop()
        timer?.cancel()
        timer = nil
        let sessionID = captureSessionID
        let elapsedSnapshot = elapsed
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isTranscribing = true
            defer { self.isTranscribing = false }
            do {
                let langRaw = UserDefaults.standard.string(forKey: SettingsKey.language) ?? TranscriptionLanguage.auto.rawValue
                let lang = TranscriptionLanguage(rawValue: langRaw)?.whisperCode
                let text = try await engine.transcribe(samples: samples, language: lang)
                transcript.applyCaptureFinal(sessionID: sessionID, rows: [
                    TranscriptSegmentRow(start: 0, end: Float(elapsedSnapshot), text: text, confirmed: true)
                ])
                let defaults = UserDefaults.standard
                let autoCopy = defaults.object(forKey: SettingsKey.autoCopy) == nil ? true : defaults.bool(forKey: SettingsKey.autoCopy)
                let autoPaste = defaults.bool(forKey: SettingsKey.autoPaste)
                if autoCopy {
                    Clipboard.copyAndPaste(text, autoPaste: autoPaste)
                }
            } catch {
                self.errorText = error.localizedDescription
            }
        }
    }
}
