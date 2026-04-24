import SwiftUI

public struct PostProcessView: View {
    @EnvironmentObject var transcript: TranscriptStore
    @EnvironmentObject var promptLibrary: PromptLibrary
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.selectedProvider) private var providerId: String = ProviderRegistry.defaultProviderId
    @AppStorage(SettingsKey.selectedPrompt)   private var promptIdString: String = ""
    @AppStorage(SettingsKey.selectedLocalModel) private var persistedLocalModel: String = "gemma2:2b"
    @AppStorage(SettingsKey.postProcessExtraInstructions) private var postProcessExtraInstructions: String = ""
    @AppStorage(SettingsKey.shippingRequireSetup) private var shippingRequireSetup: Bool = false
    @AppStorage(SettingsKey.shippingOllamaReady) private var shippingOllamaReady: Bool = false

    @State private var apiKey: String = ""
    @State private var modelOverride: String = ""
    @State private var baseURLOverride: String = ""
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?
    @State private var isTestingProvider = false
    @State private var errorText: String?
    @State private var readinessHint: String?
    @State private var remainingRequests: Int?
    @State private var showOnboarding: Bool = false
    @State private var isGemmaSetupInProgress: Bool = false
    @State private var runState: RunState = .idle
    @State private var gemmaState: GemmaLoadState = .unknown
    @State private var showOptionalAPIKey: Bool = false
    @State private var ollamaInstallPrompt: OllamaInstallPrompt?

    private enum OllamaInstallPrompt: Equatable {
        case missingCLI
        case missingDesktopApp

        var alertMessage: String {
            switch self {
            case .missingCLI:
                return "OAE doesn’t see Ollama on this Mac yet. Open the official download page in your browser to install it. When the installer finishes, come back and tap Download / load Gemma again."
            case .missingDesktopApp:
                return "OAE couldn’t find the Ollama app in your Applications folder. Open the official page to download and install Ollama, then return here and tap Download / load Gemma again."
            }
        }
    }

    private enum RunState: Equatable {
        case idle
        case running
        case cancelling
    }

    /// User-visible Gemma / Ollama readiness for Post Process (local only).
    private enum GemmaLoadState: Equatable {
        case unknown
        case checking
        case ollamaMissing
        case daemonDown(String)
        case modelNotPulled(String)
        case ready
        case error(String)
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Pin only the title row so the tall provider grid + prompt + output can scroll.
            header
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 16) {
                    localGemmaCard
                        .padding(.horizontal)

                    promptCard
                        .padding(.horizontal)

                    outputCard
                        .padding(.horizontal)

                    if let e = errorText {
                        Text(e).font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(VisualEffectBackground(material: .underWindowBackground))
        .onAppear {
            loadProviderState()
            Task { await refreshGemmaStatus() }
        }
        .onChange(of: persistedLocalModel) { _, _ in
            Task { await refreshGemmaStatus() }
        }
        .sheet(isPresented: $showOnboarding) { onboarding }
        .alert("Get Ollama for this Mac?", isPresented: Binding(
            get: { ollamaInstallPrompt != nil },
            set: { if !$0 { ollamaInstallPrompt = nil } }
        )) {
            Button("Open download page") {
                openOllamaDownloadInBrowser()
                ollamaInstallPrompt = nil
            }
            Button("Not now", role: .cancel) {
                ollamaInstallPrompt = nil
            }
        } message: {
            Text(ollamaInstallPrompt?.alertMessage ?? "")
        }
    }

    private var needsOllamaInstallOffer: Bool {
        switch gemmaState {
        case .ollamaMissing: return true
        case .daemonDown(let s):
            return s.contains("https://ollama.com") && s.localizedCaseInsensitiveContains("install")
        default: return false
        }
    }

    private func presentOllamaInstallPrompt(for prompt: OllamaInstallPrompt) {
        ollamaInstallPrompt = prompt
    }

    private func openOllamaDownloadInBrowser() {
        if let url = URL(string: "https://ollama.com/download") {
            openURL(url)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Post Process").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Local Gemma via Ollama only. Fix the status card below until it shows Ready, then Run.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showOnboarding = true
            } label: {
                Label("Setup Help", systemImage: "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.bordered)
            Button {
                runOrCancel()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRunning ? "stop.circle.fill" : "sparkles")
                    Text(isRunning ? "Cancel" : "Run")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(runDisabled)
        }
        .padding(.horizontal)
    }

    private var runDisabled: Bool {
        guard runState == .idle else { return false }
        if shippingRequireSetup && !shippingOllamaReady { return true }
        if transcript.fullText.isEmpty { return true }
        if gemmaState != .ready { return true }
        return false
    }

    private var effectiveLocalModel: String {
        let fallback = ProviderRegistry.preset(id: "local-ollama")?.defaultModel ?? "gemma2:2b"
        let m = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { return m }
        let p = persistedLocalModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? fallback : p
    }

    private var localGemmaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemma status").font(.headline)
                    Text(statusHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusHeadlineColor)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await refreshGemmaStatus() }
                } label: {
                    Label("Refresh status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(gemmaState == .checking)

                Button {
                    Task { await pullLocalModel() }
                } label: {
                    Label(isGemmaSetupInProgress ? "Setting up…" : "Download / load Gemma", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGemmaSetupInProgress)
            }

            if needsOllamaInstallOffer {
                Button {
                    presentOllamaInstallPrompt(for: gemmaState == .ollamaMissing ? .missingCLI : .missingDesktopApp)
                } label: {
                    Label("Get Ollama from the web…", systemImage: "arrow.down.app.fill")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model name")
                    .font(.caption.weight(.semibold))
                TextField("", text: $modelOverride, prompt: Text("gemma2:2b"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: modelOverride) { _, newValue in
                        let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { persistedLocalModel = t }
                    }
            }

            DisclosureGroup("Optional: API key (advanced)", isExpanded: $showOptionalAPIKey) {
                Text("Only if your gateway requires it. Default local Ollama needs no key.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                SecureField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveProviderState)
                HStack(spacing: 8) {
                    Button("Save key", action: saveProviderState)
                        .buttonStyle(.bordered)
                    Button("Clear key", role: .destructive) {
                        apiKey = ""
                        KeychainStore.remove(account: KeychainStore.accountName(forProvider: providerId))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        Task { await testProviderConnection() }
                    } label: {
                        Label(isTestingProvider ? "Testing…" : "Test HTTP", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingProvider)
                }
            }

            if let r = remainingRequests {
                Text("\(r) requests left on last remote run")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("No Ollama yet? Install from **ollama.com**, then tap **Download / load Gemma** once. OAE starts the Ollama app if needed, downloads Gemma, and turns the dot green when ready.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.25)))
    }

    private var statusHeadline: String {
        switch gemmaState {
        case .unknown: return "Not checked yet"
        case .checking: return "Checking…"
        case .ollamaMissing: return "Ollama not installed"
        case .daemonDown: return "Cannot reach Ollama"
        case .modelNotPulled(let m): return "Model not loaded: \(m)"
        case .ready: return "Ready — Gemma can run"
        case .error(let s): return "Error"
        }
    }

    private var statusDetail: String {
        switch gemmaState {
        case .unknown:
            return "Open this tab to probe automatically, or tap Refresh status."
        case .checking:
            let base = ProviderRegistry.preset(id: "local-ollama")?.baseURL ?? "http://127.0.0.1:11434"
            return "Talking to \(base) for `\(effectiveLocalModel)`…"
        case .ollamaMissing:
            return "Install from ollama.com or `brew install ollama`, then restart this check."
        case .daemonDown(let hint):
            return hint
        case .modelNotPulled(let m):
            return "The server is up but `\(m)` is not on this Mac yet. Tap **Download / load Gemma** to download it."
        case .ready:
            return "Post-processing can call your local model. \(readinessHint.map { "\($0)" } ?? "")"
        case .error(let s):
            return s
        }
    }

    private var statusHeadlineColor: Color {
        switch gemmaState {
        case .ready: return .green
        case .checking, .unknown: return .secondary
        case .ollamaMissing, .daemonDown, .modelNotPulled, .error: return .orange
        }
    }

    private var statusDotColor: Color {
        switch gemmaState {
        case .ready: return .green
        case .checking, .unknown: return .yellow
        case .ollamaMissing, .daemonDown, .modelNotPulled, .error: return .red
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Prompt").font(.headline)
                Spacer()
            }
            Picker("Prompt", selection: $promptIdString) {
                ForEach(promptLibrary.prompts) { p in
                    Text(p.name).tag(p.id.uuidString)
                }
            }
            .pickerStyle(.menu)
            if let p = selectedPrompt {
                Text(p.user.replacingOccurrences(of: "{{transcript}}", with: "…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom instructions (optional)")
                    .font(.subheadline.weight(.semibold))
                Text("Appended to the model’s system prompt for this run (e.g. notation preferences).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextEditor(text: $postProcessExtraInstructions)
                    .font(.system(size: 12))
                    .frame(minHeight: 88, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.25)))
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Output").font(.headline)
                Spacer()
                Button {
                    let payload = transcript.postProcessedText.isEmpty ? transcript.fullText : postProcessCopyableText()
                    Clipboard.copy(payload)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(transcript.postProcessedText.isEmpty && transcript.fullText.isEmpty)
            }
            // Single outer ScrollView scrolls the post-process page; keep output as plain text here.
            VStack(alignment: .leading, spacing: 10) {
                Text(transcript.postProcessedText.isEmpty ? transcript.fullText : transcript.postProcessedText)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                if !transcript.postProcessedLatex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Study supplement (inferred — verify on the board)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(transcript.postProcessedLatex)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.4)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.25)))
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Post-processing is optional and free").font(.title2.bold())
                Spacer()
                Button {
                    showOnboarding = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text("Bring your own API key. OAE stores it in your macOS Keychain and never sends it anywhere except the provider you pick. Any of these three free options will work.")
                .foregroundStyle(.secondary)

            onboardingCard(title: "Recommended · Local Ollama",
                           detail: "No API key. Runs on your laptop. Good for equations with Gemma 2B/4B.",
                           link: "https://ollama.com")
            onboardingCard(title: "Fallback · Groq",
                           detail: "Free key, no training, very fast remote inference.",
                           link: "https://console.groq.com")
            onboardingCard(title: "Fallback · GitHub Models",
                           detail: "Use your GitHub account PAT with models:read.",
                           link: "https://github.com/settings/tokens")

            HStack {
                Spacer()
                Button("Got it") {
                    UserDefaults.standard.set(true, forKey: SettingsKey.onboardedPostProcess)
                    showOnboarding = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 540)
        .interactiveDismissDisabled(false)
    }

    private func onboardingCard(title: String, detail: String, link: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = URL(string: link) {
                Link("Open", destination: url)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.3)))
    }

    // MARK: - State helpers

    private var selectedPrompt: PromptTemplate? {
        if let uuid = UUID(uuidString: promptIdString),
           let p = promptLibrary.prompts.first(where: { $0.id == uuid }) { return p }
        return promptLibrary.prompts.first
    }

    private func loadProviderState() {
        providerId = "local-ollama"
        guard let preset = ProviderRegistry.preset(id: "local-ollama") else { return }
        apiKey = KeychainStore.get(account: KeychainStore.accountName(forProvider: providerId)) ?? ""
        if modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let p = persistedLocalModel.trimmingCharacters(in: .whitespacesAndNewlines)
            modelOverride = p.isEmpty ? preset.defaultModel : p
        }
        baseURLOverride = ""
    }

    /// Maps `LocalReadinessError.daemonUnreachable` payloads: URL-like roots vs full sentences from `ensureOllamaDaemonReachable`.
    private static func mapDaemonUnreachableHint(_ base: String) -> String {
        let t = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            return "Server not reachable at \(t). Tap **Download / load Gemma** — OAE will try to start Ollama and fetch your model — or open the Ollama app, then tap **Refresh status**."
        }
        return t
    }

    @MainActor
    private func refreshGemmaStatus() async {
        providerId = "local-ollama"
        guard let preset = ProviderRegistry.preset(id: "local-ollama") else { return }
        gemmaState = .checking
        readinessHint = nil

        if !PostProcessor.isOllamaCLIInstalled() {
            gemmaState = .ollamaMissing
            errorText = nil
            return
        }

        let model = effectiveLocalModel
        let config = ProviderUserConfig(presetId: preset.id, model: model, baseURLOverride: nil)
        do {
            try await PostProcessor().verifyLocalOllama(baseURL: config.effectiveBaseURL, model: config.model)
            gemmaState = .ready
            readinessHint = "Model `\(model)` responded on \(config.effectiveBaseURL)."
            errorText = nil
        } catch let e as PostProcessor.LocalReadinessError {
            errorText = nil
            switch e {
            case .ollamaMissing:
                gemmaState = .ollamaMissing
            case .daemonUnreachable(let base):
                gemmaState = .daemonDown(Self.mapDaemonUnreachableHint(base))
            case .modelMissing(let missing):
                gemmaState = .modelNotPulled(missing)
            }
        } catch {
            gemmaState = .error(error.localizedDescription)
        }
    }

    private func applyVerifyFailureToGemmaState(_ error: Error) {
        if let e = error as? PostProcessor.LocalReadinessError {
            switch e {
            case .ollamaMissing:
                gemmaState = .ollamaMissing
            case .daemonUnreachable(let base):
                gemmaState = .daemonDown(Self.mapDaemonUnreachableHint(base))
            case .modelMissing(let missing):
                gemmaState = .modelNotPulled(missing)
            }
        } else {
            gemmaState = .error(error.localizedDescription)
        }
    }

    private func saveProviderState() {
        let account = KeychainStore.accountName(forProvider: providerId)
        if apiKey.isEmpty {
            KeychainStore.remove(account: account)
        } else {
            try? KeychainStore.set(apiKey, account: account)
        }
        if ProviderRegistry.preset(id: providerId)?.isCustom == true {
            UserDefaults.standard.set(baseURLOverride, forKey: "oae.custom.baseurl")
        }
    }

    private func run() async {
        if isRunning { return }
        guard let preset = ProviderRegistry.preset(id: providerId) else { return }
        guard var prompt = selectedPrompt else { return }
        let source = transcript.fullText
        guard !source.isEmpty else { return }
        if !isKeyOptionalProvider && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorText = "This provider requires an API key."
            return
        }

        let extra = postProcessExtraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            prompt.system += "\n\n### User-provided addendum\n\(extra)"
        }

        let config = ProviderUserConfig(
            presetId: preset.id,
            model: effectiveLocalModel,
            baseURLOverride: preset.isCustom ? baseURLOverride : nil
        )
        let req = PostProcessor.Request(transcript: source, prompt: prompt,
                                        provider: config, apiKey: apiKey)
        if preset.id == "local-ollama" {
            do {
                try await PostProcessor().verifyLocalOllama(baseURL: config.effectiveBaseURL, model: config.model)
            } catch {
                applyVerifyFailureToGemmaState(error)
                errorText = error.localizedDescription
                return
            }
        }

        isRunning = true
        runState = .running
        transcript.isPostProcessing = true
        transcript.setPostProcessedText("")
        transcript.setPostProcessedLatex("")
        errorText = nil
        defer {
            isRunning = false
            runState = .idle
            transcript.isPostProcessing = false
            runTask = nil
        }

        do {
            var tokenBuffer = ""
            var lastFlush = Date()
            for try await event in PostProcessor().stream(req) {
                switch event {
                case .token(let t):
                    if Task.isCancelled { return }
                    tokenBuffer += t
                    let shouldFlush = tokenBuffer.count >= 80 || Date().timeIntervalSince(lastFlush) > 0.10
                    if shouldFlush {
                        appendOutputChunk(tokenBuffer)
                        tokenBuffer = ""
                        lastFlush = Date()
                    }
                case .done(let full):
                    if !tokenBuffer.isEmpty {
                        appendOutputChunk(tokenBuffer)
                        tokenBuffer = ""
                    }
                    if !full.isEmpty { applyPostProcessOutput(full) }
                    Clipboard.copy(postProcessCopyableText())
                case .rateLimitInfo(let rem, _):
                    remainingRequests = rem
                }
            }
        } catch {
            if !Task.isCancelled {
                errorText = error.localizedDescription
            }
        }
    }

    private func runOrCancel() {
        if runState == .cancelling { return }
        if isRunning {
            runState = .cancelling
            runTask?.cancel()
            isRunning = false
            transcript.isPostProcessing = false
            errorText = "Post-processing cancelled."
            return
        }
        runTask = Task { await run() }
    }

    private var isKeyOptionalProvider: Bool {
        ProviderRegistry.preset(id: providerId)?.id == "local-ollama"
    }

    private func applyPostProcessOutput(_ full: String) {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        var unicodeCandidate = trimmed
        var latexCandidate = ""
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let unicode = (obj["unicode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let latex = (obj["latex"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !unicode.isEmpty || !latex.isEmpty {
                unicodeCandidate = unicode.isEmpty ? trimmed : unicode
                latexCandidate = latex
            }
        }
        if unicodeCandidate.lowercased().contains("\"unicode\""),
           let start = unicodeCandidate.range(of: "\"unicode\""),
           let colon = unicodeCandidate[start.upperBound...].firstIndex(of: ":") {
            let tail = unicodeCandidate[unicodeCandidate.index(after: colon)...]
            unicodeCandidate = tail.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
                .replacingOccurrences(of: "latex:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let (lecture, study) = Self.splitAtStudySupplementMarker(unicodeCandidate)
        if latexCandidate.isEmpty, !study.isEmpty {
            transcript.applyPostProcessedUnicode(lecture, latex: study)
        } else {
            transcript.applyPostProcessedUnicode(unicodeCandidate, latex: latexCandidate)
        }
    }

    /// Splits scientific post-process output after `<<<OAE_STUDY_SUPPLEMENT>>>`. Lecture → main text; supplement stored in `postProcessedLatex` for UI (not necessarily LaTeX).
    private static func splitAtStudySupplementMarker(_ text: String) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = "<<<OAE_STUDY_SUPPLEMENT>>>"
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (i, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == marker {
            let lecture = lines[0..<i].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let study = lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return (lecture.isEmpty ? trimmed : lecture, study)
        }
        return (trimmed, "")
    }

    private func postProcessCopyableText() -> String {
        let t = transcript.postProcessedText
        let s = transcript.postProcessedLatex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return t }
        return t + "\n\n———\nStudy supplement (inferred — verify on the board)\n———\n\n" + s
    }

    private func testProviderConnection() async {
        guard let preset = ProviderRegistry.preset(id: "local-ollama") else { return }
        isTestingProvider = true
        defer { isTestingProvider = false }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            await refreshGemmaStatus()
            if gemmaState == .ready {
                errorText = "Local Gemma check passed."
            } else if errorText == nil {
                errorText = "Local check finished — see Gemma status above."
            }
            return
        }

        let probePrompt = PromptTemplate(
            name: "Probe",
            system: "Reply with exactly: OK",
            user: "Say OK.",
            temperature: 0.0
        )
        let config = ProviderUserConfig(
            presetId: preset.id,
            model: effectiveLocalModel,
            baseURLOverride: preset.isCustom ? baseURLOverride : nil
        )
        let req = PostProcessor.Request(transcript: "test", prompt: probePrompt, provider: config, apiKey: apiKey)
        do {
            _ = try await PostProcessor().runOnce(req)
            errorText = "HTTP test passed (custom gateway)."
        } catch {
            errorText = "HTTP test failed: \(error.localizedDescription)"
        }
    }

    private func pullLocalModel() async {
        guard let preset = ProviderRegistry.preset(id: "local-ollama") else { return }
        let model = effectiveLocalModel
        let config = ProviderUserConfig(presetId: preset.id, model: model, baseURLOverride: preset.isCustom ? baseURLOverride : nil)

        if !PostProcessor.isOllamaCLIInstalled() {
            gemmaState = .ollamaMissing
            errorText = nil
            presentOllamaInstallPrompt(for: .missingCLI)
            return
        }

        isGemmaSetupInProgress = true
        defer { isGemmaSetupInProgress = false }
        errorText = nil
        gemmaState = .checking
        readinessHint = "Starting Ollama if needed…"

        do {
            try await PostProcessor().ensureOllamaDaemonReachable(openAICompatibleBaseURL: config.effectiveBaseURL)
        } catch is CancellationError {
            readinessHint = nil
            await refreshGemmaStatus()
            return
        } catch {
            applyVerifyFailureToGemmaState(error)
            if let le = error as? PostProcessor.LocalReadinessError,
               case .daemonUnreachable(let s) = le,
               s.contains("https://ollama.com") {
                presentOllamaInstallPrompt(for: .missingDesktopApp)
            }
            readinessHint = nil
            return
        }

        readinessHint = "Downloading Gemma — this can take a minute the first time…"
        do {
            let status = try await runShellCommand("ollama pull \(model)")
            if status == 0 {
                readinessHint = "Finished downloading \(model)."
                await refreshGemmaStatus()
            } else {
                gemmaState = .error("The model download didn’t finish. Check that Ollama is running, then tap Download / load Gemma again.")
            }
        } catch {
            gemmaState = .error("Could not download the model. Check your connection and try again.")
        }
    }

    private func appendOutputChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        let updated = transcript.postProcessedText + chunk
        let maxChars = 20_000
        if updated.count > maxChars {
            transcript.setPostProcessedText("…" + String(updated.suffix(maxChars)))
        } else {
            transcript.setPostProcessedText(updated)
        }
    }

    private func runShellCommand(_ command: String) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-lc", command]
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
