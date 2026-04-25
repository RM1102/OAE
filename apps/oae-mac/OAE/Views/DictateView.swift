import SwiftUI
import Combine
import WhisperKit

public struct DictateView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @EnvironmentObject var transcript: TranscriptStore

    @AppStorage(SettingsKey.language) private var languageRaw: String = TranscriptionLanguage.auto.rawValue
    @AppStorage(SettingsKey.confirmationSegments) private var confirmationSegments: Int = 2
    @AppStorage(SettingsKey.lowLatencyLive) private var lowLatencyLive: Bool = true
    @AppStorage(SettingsKey.dictateLivePostProcess) private var dictateLivePostProcess: Bool = false
    @AppStorage(SettingsKey.dictateLivePostProcessWordStep) private var dictateLiveWordStep: Int = 22
    @AppStorage(SettingsKey.dictateLivePostProcessStudyStep) private var dictateLiveStudyStep: Int = 150
    @AppStorage(SettingsKey.liveStreamingPreset) private var liveStreamingPresetRaw: String = LiveStreamer.StreamingPreset.ultraLowLatency.rawValue
    @AppStorage(SettingsKey.dictateRewriteLookbackWords) private var rewriteLookbackWords: Int = 10
    @AppStorage(SettingsKey.shippingRequireSetup) private var shippingRequireSetup: Bool = false
    @AppStorage(SettingsKey.shippingOllamaReady) private var shippingOllamaReady: Bool = false

    @StateObject private var livePostProcessor = DictateLivePostProcessCoordinator()
    @State private var streamer = LiveStreamer()
    @State private var isRunning = false
    @State private var activeSessionID = UUID()
    @State private var streamState: StreamState = .idle
    @State private var levels: [Float] = Array(repeating: 0, count: 64)
    @State private var errorText: String?
    @State private var pendingSnapshot: String = ""
    @State private var pendingSince = Date()
    @State private var lastForcedFlush: String = ""
    @State private var pendingWordCountSnapshot: Int = 0
    @State private var pendingWordCountSince = Date()
    @State private var lastSpeechDetectedAt = Date()
    @State private var firstPartialAfterSpeechAt: Date?
    @State private var firstCommitAfterSpeechAt: Date?
    @State private var partialLagSamplesMs: [Double] = []
    @State private var commitLagSamplesMs: [Double] = []
    @State private var rewriteSamples: [Double] = []
    /// Mirrored from `engine.isReadyForTranscription` so `.disabled` on buttons does not read
    /// `@EnvironmentObject` during AppKit gesture flushing (macOS 26 / SwiftUI bridge crash).
    @State private var transcriptionReady = false

    private enum StreamState: String {
        case idle
        case starting
        case running
        case stopping
        case failed
    }

    private struct EndpointingPolicy {
        let silenceLevel: Float
        let stableDuration: TimeInterval
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                WaveformView(levels: levels, active: isRunning)
                    .frame(height: 64)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.quaternary.opacity(0.35))
                    )
                    .padding(.horizontal)

                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.quaternary.opacity(0.25))
                    TranscriptView()
                }
                .padding(.horizontal)

                footer
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
        .onAppear {
            transcript.activate(source: .dictate)
            transcriptionReady = engine.isReadyForTranscription
        }
        .onReceive(engine.$isReadyForTranscription) { transcriptionReady = $0 }
        .onDisappear {
            // Hard lifecycle teardown: if the user leaves Dictate while a stream is
            // active, stop it immediately so transcription cannot continue headless.
            if isRunning {
                Task { await stopSession() }
            }
        }
        .onChange(of: transcript.fullText) { _, newValue in
            guard isRunning else { return }
            livePostProcessor.onTranscriptChanged(
                sessionID: activeSessionID,
                fullText: newValue,
                enabled: dictateLivePostProcess,
                wordStepLight: dictateLiveWordStep,
                wordStepStudy: dictateLiveStudyStep
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictate").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Continuous live transcription. Speak naturally.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let e = errorText {
                Text(e).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            HStack(spacing: 8) {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Image(systemName: isRunning ? "stop.circle.fill" : "record.circle.fill")
                        Text(isRunning ? "Stop" : "Start")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .accentColor)
                .disabled(!isRunning && !transcriptionReady)
                .keyboardShortcut(.space, modifiers: [.command])

                if isRunning {
                    Button("Force Stop") {
                        Task { await forceStopSession() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .foregroundStyle(.red)
                    .help("Immediately tear down the live stream if Stop is unresponsive.")
                }
                if isRunning {
                    Text(metricsLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Live latency: partial p50/p95, commit p50/p95, and rewrite rate.")
                }
            }
        }
        .padding(.horizontal)
    }

    private var effectiveConfirmationDepth: Int {
        if selectedPreset == .ultraLowLatency { return 1 }
        if lowLatencyLive { return 1 }
        return min(max(1, confirmationSegments), 2)
    }

    private var selectedPreset: LiveStreamer.StreamingPreset {
        LiveStreamer.StreamingPreset(rawValue: liveStreamingPresetRaw) ?? .ultraLowLatency
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("LocalAgreement-\(effectiveConfirmationDepth)", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Live mode", selection: $liveStreamingPresetRaw) {
                ForEach(LiveStreamer.StreamingPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            Stepper(value: $rewriteLookbackWords, in: 6...18) {
                Text("Rewrite lookback: \(rewriteLookbackWords)w")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .help("How many recent words Whisper is allowed to revise in the merged **saved** transcript when it corrects itself. The subtitle island uses a separate engine confirmed vs volatile feed, so this lookback mainly affects the Dictate text pane, not island geometry.")
            Toggle(isOn: $dictateLivePostProcess) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Live math (Ollama)")
                        .font(.caption.weight(.semibold))
                    Text("Unicode tail + study batches while you speak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
            .disabled(shippingRequireSetup && !shippingOllamaReady)
            .help("Uses local Gemma in the background (~\(dictateLiveWordStep) words per Unicode pass, ~\(dictateLiveStudyStep) words per study batch, after a short pause).")
            if dictateLivePostProcess, transcript.dictateLivePostProcessBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
            Spacer()
            Button {
                Clipboard.copy(transcript.fullText)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(transcript.fullText.isEmpty)
        }
        .padding(.horizontal)
    }

    private func toggle() {
        Task { await isRunning ? stopSession() : startSession() }
    }

    @MainActor
    private func startSession() async {
        guard !isRunning else { return }

        if engine.isLoading {
            errorText = "Model is still loading. Please wait until loading reaches 100%."
            streamState = .failed
            return
        }
        if !engine.isReadyForTranscription {
            if let err = engine.lastError, !err.isEmpty {
                errorText = "Model load failed: \(err)"
            } else {
                errorText = "Model is not loaded yet. Retry from the yellow banner."
            }
            streamState = .failed
            return
        }

        streamState = .starting
        errorText = nil
        isRunning = true
        pendingSnapshot = ""
        lastForcedFlush = ""
        pendingSince = Date()

        let runID = transcript.beginSession(source: .dictate)
        activeSessionID = runID
        livePostProcessor.resetForNewSession(sessionID: runID)
        do {
            try await streamer.start(
                language: TranscriptionLanguage(rawValue: languageRaw)?.whisperCode,
                requiredSegmentsForConfirmation: effectiveConfirmationDepth,
                preset: selectedPreset,
                onState: { state, event in
                    guard runID == activeSessionID else { return }
                    guard streamState == .starting || streamState == .running else { return }
                    streamState = .running
                    update(with: state, eventTimestamp: event.emittedAt)
                }
            )
            // `start()` returns only after stop; if it returns during an active session,
            // normalize state to idle.
            if runID == activeSessionID, streamState != .stopping {
                streamState = .idle
                isRunning = false
            }
        } catch {
            if runID == activeSessionID {
                streamState = .failed
                isRunning = false
                errorText = userFacingError(error)
            }
        }
    }

    @MainActor
    private func stopSession() async {
        streamState = .stopping
        await streamer.stop()
        livePostProcessor.sessionEnded()
        // Invalidate any stale callback closures from previous session.
        activeSessionID = UUID()
        isRunning = false
        streamState = .idle
    }

    /// Hard reset: same mic teardown as Stop, plus clears any error banner (for “nothing responds” moments).
    @MainActor
    private func forceStopSession() async {
        streamState = .stopping
        await streamer.stop()
        livePostProcessor.sessionEnded()
        activeSessionID = UUID()
        isRunning = false
        streamState = .idle
        errorText = nil
    }

    private func update(with state: AudioStreamTranscriber.State, eventTimestamp: Date) {
        levels = state.bufferEnergy.suffix(64).map { $0 }
        while levels.count < 64 { levels.insert(0, at: 0) }
        if let currentEnergy = state.bufferEnergy.last,
           currentEnergy > 0.07,
           eventTimestamp.timeIntervalSince(lastSpeechDetectedAt) > 0.25 {
            lastSpeechDetectedAt = eventTimestamp
            firstPartialAfterSpeechAt = nil
            firstCommitAfterSpeechAt = nil
        }

        let confirmedRows = state.confirmedSegments.map { seg in
            TranscriptSegmentRow(id: UUID(), start: seg.start, end: seg.end, text: seg.text, confirmed: true)
        }

        let partial = state.unconfirmedSegments.map { $0.text }.joined(separator: " ")
        let currentRaw = state.currentText.trimmingCharacters(in: .whitespaces)
        let currentText = Self.strippingWhisperKitIdlePlaceholder(currentRaw)
        let pending = (partial.isEmpty ? currentText : (partial + " " + currentText))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if pending != pendingSnapshot {
            pendingSnapshot = pending
            pendingSince = Date()
            if !pending.isEmpty {
                let now = Date()
                if firstPartialAfterSpeechAt == nil {
                    firstPartialAfterSpeechAt = now
                    let partialLag = max(0, now.timeIntervalSince(lastSpeechDetectedAt) * 1000)
                    appendSample(partialLag, to: &partialLagSamplesMs)
                }
            }
        }

        let pendingWords = wordCount(pending)
        if pendingWords != pendingWordCountSnapshot {
            pendingWordCountSnapshot = pendingWords
            pendingWordCountSince = Date()
        }

        let endpointing = adaptiveEndpointingPolicy(state: state)
        let recentlySilent = state.bufferEnergy.suffix(3).allSatisfy { $0 < endpointing.silenceLevel }
        let pendingStable = Date().timeIntervalSince(pendingSince) > endpointing.stableDuration
        // Promote pending text after a short pause even if LocalAgreement still holds segments back.
        if recentlySilent,
           pendingStable,
           !pending.isEmpty,
           pending != lastForcedFlush,
           transcript.confirmedSegments.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) != pending {
            var rows = confirmedRows
            let lastEnd = rows.last?.end ?? 0
            rows.append(TranscriptSegmentRow(start: lastEnd, end: lastEnd + 0.8, text: pending, confirmed: true))
            transcript.applyDictateUpdate(sessionID: activeSessionID, confirmedRows: rows, partial: "", rewriteLookbackWords: rewriteLookbackWords)
            let commitLag = max(0, Date().timeIntervalSince(lastSpeechDetectedAt) * 1000)
            appendSample(commitLag, to: &commitLagSamplesMs)
            lastForcedFlush = pending
            pendingSnapshot = ""
            pendingSince = Date()
            firstPartialAfterSpeechAt = nil
            firstCommitAfterSpeechAt = nil
            return
        }

        if firstCommitAfterSpeechAt == nil, !confirmedRows.isEmpty {
            firstCommitAfterSpeechAt = Date()
            let commitLag = max(0, Date().timeIntervalSince(lastSpeechDetectedAt) * 1000)
            appendSample(commitLag, to: &commitLagSamplesMs)
        }
        let previousFull = transcript.fullText
        transcript.applyDictateUpdate(sessionID: activeSessionID, confirmedRows: confirmedRows, partial: pending, rewriteLookbackWords: rewriteLookbackWords)
        let rewrite = rewriteRate(previous: previousFull, current: transcript.fullText)
        appendSample(rewrite, to: &rewriteSamples)
    }

    private func userFacingError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("microphone") || msg.contains("audio") {
            return "Microphone access failed. Enable it in System Settings > Privacy & Security > Microphone."
        }
        if msg.contains("not loaded") || msg.contains("model") {
            if let last = engine.lastError, !last.isEmpty {
                return "Model load failed: \(last)"
            }
            return "Model is not loaded yet. Please retry after loading finishes."
        }
        return error.localizedDescription
    }

    /// WhisperKit sets this while VAD skips or the buffer is short; do not treat it as real partial text.
    private static func strippingWhisperKitIdlePlaceholder(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.compare("Waiting for speech...", options: .caseInsensitive) == .orderedSame {
            return ""
        }
        if trimmed.lowercased().hasPrefix("waiting for speech") {
            return ""
        }
        return text
    }

    private func adaptiveEndpointingPolicy(state: AudioStreamTranscriber.State) -> EndpointingPolicy {
        let noiseFloor = state.bufferEnergy.suffix(24).reduce(0, +) / Float(max(1, min(24, state.bufferEnergy.count)))
        let wordDelta = max(0, pendingWordCountSnapshot)
        let wordRate = Double(wordDelta) / max(0.25, Date().timeIntervalSince(pendingWordCountSince))
        // Fast speech: commit sooner. Noisy room: wait slightly longer to avoid false finalization.
        let stableDuration: TimeInterval
        if wordRate > 2.2 {
            stableDuration = 0.1
        } else if noiseFloor > 0.065 {
            stableDuration = 0.2
        } else {
            stableDuration = selectedPreset == .ultraLowLatency ? 0.12 : 0.16
        }
        let silenceLevel: Float = noiseFloor > 0.065 ? 0.05 : 0.06
        return EndpointingPolicy(silenceLevel: silenceLevel, stableDuration: stableDuration)
    }

    private func wordCount(_ value: String) -> Int {
        value.split(whereSeparator: \.isWhitespace).count
    }

    private func appendSample(_ value: Double, to array: inout [Double], maxCount: Int = 160) {
        guard value.isFinite else { return }
        array.append(value)
        if array.count > maxCount {
            array.removeFirst(array.count - maxCount)
        }
    }

    private func percentile(_ samples: [Double], _ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let idx = Int(Double(sorted.count - 1) * p)
        return sorted[max(0, min(sorted.count - 1, idx))]
    }

    private func rewriteRate(previous: String, current: String) -> Double {
        let old = previous.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = current.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !old.isEmpty else { return 0 }
        let shared = min(old.count, new.count)
        guard shared > 0 else { return 1 }
        let changed = zip(old.prefix(shared), new.prefix(shared)).filter { $0 != $1 }.count
        return Double(changed) / Double(shared)
    }

    private var metricsLabel: String {
        let p50Partial = Int(percentile(partialLagSamplesMs, 0.5))
        let p95Partial = Int(percentile(partialLagSamplesMs, 0.95))
        let p50Commit = Int(percentile(commitLagSamplesMs, 0.5))
        let p95Commit = Int(percentile(commitLagSamplesMs, 0.95))
        let rewritePct = Int((percentile(rewriteSamples, 0.95)) * 100)
        return "P \(p50Partial)/\(p95Partial)ms  C \(p50Commit)/\(p95Commit)ms  R95 \(rewritePct)%"
    }
}
