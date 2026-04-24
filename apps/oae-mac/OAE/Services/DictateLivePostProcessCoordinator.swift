import Foundation

/// Debounced background post-processing while Dictate is running (Unicode tail + occasional study batch).
@MainActor
public final class DictateLivePostProcessCoordinator: ObservableObject {
    private let transcript: TranscriptStore

    private var debounceTask: Task<Void, Never>?
    private var lightTask: Task<Void, Never>?
    private var studyTask: Task<Void, Never>?

    private var lastLightAtTotalWords = 0
    private var lastStudyAtTotalWords = 0
    private var boundSessionID: UUID?
    private var lastTextFingerprint: String = ""

    public init(transcript: TranscriptStore = .shared) {
        self.transcript = transcript
    }

    public func resetForNewSession(sessionID: UUID) {
        debounceTask?.cancel()
        lightTask?.cancel()
        studyTask?.cancel()
        debounceTask = nil
        lightTask = nil
        studyTask = nil
        lastLightAtTotalWords = 0
        lastStudyAtTotalWords = 0
        boundSessionID = sessionID
        lastTextFingerprint = ""
        transcript.clearDictateLivePostProcessPreviews()
    }

    public func sessionEnded() {
        debounceTask?.cancel()
        debounceTask = nil
        lightTask?.cancel()
        studyTask?.cancel()
        lightTask = nil
        studyTask = nil
        boundSessionID = nil
    }

    /// Call on each Dictate transcript update while `isRunning`.
    public func onTranscriptChanged(
        sessionID: UUID,
        fullText: String,
        enabled: Bool,
        wordStepLight: Int,
        wordStepStudy: Int
    ) {
        guard enabled, boundSessionID == sessionID else { return }
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcript.clearDictateLivePostProcessPreviews()
            return
        }
        lastTextFingerprint = trimmed

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !Task.isCancelled else { return }
            guard sessionID == self.boundSessionID else { return }
            guard trimmed == self.lastTextFingerprint else { return }
            await self.runGates(
                snapshot: trimmed,
                sessionID: sessionID,
                wordStepLight: max(12, wordStepLight),
                wordStepStudy: max(60, wordStepStudy)
            )
        }
    }

    private func runGates(
        snapshot: String,
        sessionID: UUID,
        wordStepLight: Int,
        wordStepStudy: Int
    ) async {
        guard sessionID == boundSessionID else { return }

        let words = Self.wordCount(snapshot)
        let deltaLight = words - lastLightAtTotalWords
        let deltaStudy = words - lastStudyAtTotalWords

        var startedLight = false
        var startedStudy = false

        if deltaLight >= wordStepLight {
            lastLightAtTotalWords = words
            startedLight = true
        }
        if words >= 60, deltaStudy >= wordStepStudy {
            lastStudyAtTotalWords = words
            startedStudy = true
        }

        if startedLight {
            lightTask?.cancel()
            lightTask = Task { [weak self] in
                await self?.runLight(snapshot: snapshot, sessionID: sessionID)
            }
        }
        if startedStudy {
            studyTask?.cancel()
            studyTask = Task { [weak self] in
                await self?.runStudy(snapshot: snapshot, sessionID: sessionID)
            }
        }
    }

    private static func wordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    private static func tail(_ s: String, maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        return String(s.suffix(maxChars))
    }

    private func providerConfig() -> (ProviderUserConfig, String)? {
        guard let preset = ProviderRegistry.preset(id: "local-ollama") else { return nil }
        let modelKey = SettingsKey.selectedLocalModel
        let model = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? preset.defaultModel
        let cfg = ProviderUserConfig(presetId: preset.id, model: model, baseURLOverride: nil)
        let apiKey = KeychainStore.get(account: KeychainStore.accountName(forProvider: preset.id)) ?? ""
        return (cfg, apiKey)
    }

    private func runLight(snapshot: String, sessionID: UUID) async {
        guard sessionID == boundSessionID else { return }
        guard let (cfg, apiKey) = providerConfig() else { return }
        do {
            try await PostProcessor().verifyLocalOllama(baseURL: cfg.effectiveBaseURL, model: cfg.model)
        } catch {
            return
        }

        transcript.beginDictateLiveBackgroundWork()
        defer { transcript.endDictateLiveBackgroundWork() }
        let excerpt = Self.tail(snapshot, maxChars: 1100)
        guard let preset = liveLightBuiltin() else { return }
        let userBody = preset.user.replacingOccurrences(of: "{{transcript}}", with: excerpt)
        let prompt = PromptTemplate(id: preset.id, name: preset.name, system: preset.system,
                                     user: userBody, temperature: preset.temperature, isBuiltin: true)
        let req = PostProcessor.Request(transcript: excerpt, prompt: prompt, provider: cfg, apiKey: apiKey)

        var accumulated = ""
        do {
            for try await ev in PostProcessor().stream(req) {
                guard sessionID == boundSessionID else { return }
                switch ev {
                case .token(let t):
                    accumulated += t
                case .done(let full):
                    let out = full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                        : full.trimmingCharacters(in: .whitespacesAndNewlines)
                    transcript.updateDictateLivePostProcessPreviews(math: out, study: nil)
                case .rateLimitInfo:
                    break
                }
            }
        } catch {
            // Silent: do not disturb Dictate with banners.
        }
    }

    private func runStudy(snapshot: String, sessionID: UUID) async {
        guard sessionID == boundSessionID else { return }
        guard let (cfg, apiKey) = providerConfig() else { return }
        do {
            try await PostProcessor().verifyLocalOllama(baseURL: cfg.effectiveBaseURL, model: cfg.model)
        } catch {
            return
        }

        transcript.beginDictateLiveBackgroundWork()
        defer { transcript.endDictateLiveBackgroundWork() }
        let excerpt = Self.tail(snapshot, maxChars: 4200)
        guard let preset = liveStudyBatchBuiltin() else { return }
        let userBody = preset.user.replacingOccurrences(of: "{{transcript}}", with: excerpt)
        let prompt = PromptTemplate(id: preset.id, name: preset.name, system: preset.system,
                                     user: userBody, temperature: preset.temperature, isBuiltin: true)
        let req = PostProcessor.Request(transcript: excerpt, prompt: prompt, provider: cfg, apiKey: apiKey)

        var accumulated = ""
        do {
            for try await ev in PostProcessor().stream(req) {
                guard sessionID == boundSessionID else { return }
                switch ev {
                case .token(let t):
                    accumulated += t
                case .done(let full):
                    let raw = full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                        : full.trimmingCharacters(in: .whitespacesAndNewlines)
                    transcript.updateDictateLivePostProcessPreviews(math: nil, study: raw)
                case .rateLimitInfo:
                    break
                }
            }
        } catch {
            // Silent.
        }
    }

    private func liveLightBuiltin() -> PromptTemplate? {
        PromptLibrary.builtinTemplates.first { $0.id.uuidString == "00000000-0000-0000-0000-00000000AA0C" }
    }

    private func liveStudyBatchBuiltin() -> PromptTemplate? {
        PromptLibrary.builtinTemplates.first { $0.id.uuidString == "00000000-0000-0000-0000-00000000AA0D" }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
