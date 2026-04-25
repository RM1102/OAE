import SwiftUI
import AppKit

@MainActor
final class ProfessorSetupCoordinator: ObservableObject {
    enum Step: Int, Comparable {
        case idle = 0
        case installingWhisper
        case installingOllama
        case startingOllama
        case pullingOllamaModel
        case done
        case error
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @Published var step: Step = .idle
    @Published var isWorking: Bool = false
    @Published var statusText: String = ""
    @Published var errorText: String?
    @Published var progress: Double = 0

    private let modelStore: ModelStore
    private let nativeRoot = "http://127.0.0.1:11434"

    init(modelStore: ModelStore) {
        self.modelStore = modelStore
    }

    /// Returns true if the setup sheet should be presented. Silently marks setup complete if everything is already ready.
    func evaluateReadinessOnLaunch(requiredWhisper: String, requiredOllamaModel: String) async -> Bool {
        if UserDefaults.standard.bool(forKey: SettingsKey.shippingSetupCompleted) { return false }

        let modelReady = modelStore.isInstalled(requiredWhisper)
        let ollamaReady = await isOllamaModelReady(model: requiredOllamaModel)
        if modelReady && ollamaReady {
            UserDefaults.standard.set(true, forKey: SettingsKey.shippingModelsReady)
            UserDefaults.standard.set(true, forKey: SettingsKey.shippingOllamaReady)
            UserDefaults.standard.set(true, forKey: SettingsKey.shippingSetupCompleted)
            step = .done
            return false
        }
        return true
    }

    var requiresSetup: Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.shippingSetupCompleted)
    }

    var isComplete: Bool {
        step == .done || UserDefaults.standard.bool(forKey: SettingsKey.shippingSetupCompleted)
    }

    /// Kept for backward compatibility with earlier call sites.
    func refreshState() {}

    func runAutoSetup(requiredWhisper: String, requiredOllamaModel: String) async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        // Step 1: Whisper model. Prefer bundled payload, fall back to network download.
        step = .installingWhisper
        progress = 0
        if !modelStore.isInstalled(requiredWhisper) {
            statusText = "Preparing transcription model..."
            var installed = false
            if hasBundledModels() {
                statusText = "Installing included transcription model..."
                do {
                    try modelStore.installBundledModelsIfAvailable(requiredModel: requiredWhisper)
                    installed = true
                } catch {
                    NSLog("[OAE] bundled whisper install failed: \(error.localizedDescription); falling back to network download")
                }
            }
            if !installed {
                statusText = "Downloading transcription model (~630 MB)..."
                do {
                    try await modelStore.download(requiredWhisper)
                } catch {
                    errorText = "Couldn't download transcription model: \(error.localizedDescription)"
                    step = .error
                    return
                }
            }
        }
        UserDefaults.standard.set(true, forKey: SettingsKey.shippingModelsReady)

        // Engine load was deferred in bootstrap if the model wasn't on disk yet. Trigger
        // it now so the main window becomes usable without requiring a restart.
        if !TranscriptionEngine.shared.isReadyForTranscription {
            statusText = "Loading transcription model..."
            do {
                try await TranscriptionEngine.shared.load(
                    modelName: requiredWhisper,
                    modelFolder: modelStore.rootURL
                )
            } catch {
                NSLog("[OAE] engine reload after bundled install failed: \(error.localizedDescription)")
            }
        }

        // Step 2: Ollama install.
        step = .installingOllama
        progress = 0
        statusText = "Preparing local AI assistant..."
        var ollamaAlreadyPresent = PostProcessor.isOllamaCLIInstalled()
            || FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
            || FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Applications/Ollama.app")
        if !ollamaAlreadyPresent {
            ollamaAlreadyPresent = await OllamaBootstrap.ping(nativeRoot: nativeRoot)
        }
        if !ollamaAlreadyPresent {
            let ok = await autoInstallOllama()
            if !ok {
                if errorText == nil {
                    errorText = "Couldn't install Ollama automatically. We opened ollama.com/download — drag it to Applications, then press Try again."
                }
                if let url = URL(string: "https://ollama.com/download") {
                    NSWorkspace.shared.open(url)
                }
                step = .error
                return
            }
        }

        // Step 3: Start Ollama daemon.
        step = .startingOllama
        progress = 0
        statusText = "Starting local AI assistant..."
        _ = OllamaBootstrap.openOllamaApp()
        let reachable = await OllamaBootstrap.waitForDaemon(nativeRoot: nativeRoot, timeoutSeconds: 90)
        guard reachable else {
            errorText = "Ollama didn’t start in time. Open Ollama from your Applications folder, then press Try again."
            step = .error
            return
        }

        // Step 4: Pull local AI model (via HTTP so we don't need the CLI on PATH).
        step = .pullingOllamaModel
        progress = 0
        statusText = "Downloading local AI model (\(requiredOllamaModel))..."
        do {
            try await pullOllamaModelViaHTTP(model: requiredOllamaModel)
        } catch {
            errorText = "Couldn't fetch local AI model: \(error.localizedDescription)"
            step = .error
            return
        }
        UserDefaults.standard.set(true, forKey: SettingsKey.shippingOllamaReady)

        step = .done
        progress = 1
        statusText = "All set!"
        UserDefaults.standard.set(true, forKey: SettingsKey.shippingSetupCompleted)
    }

    // MARK: - Helpers

    private func hasBundledModels() -> Bool {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("BundledModels", isDirectory: true) else {
            return false
        }
        return FileManager.default.fileExists(atPath: bundled.path)
    }

    /// Best-effort silent Ollama install. Tries Homebrew first, then Ollama's official zip into ~/Applications.
    private func autoInstallOllama() async -> Bool {
        if await runShell("command -v brew >/dev/null 2>&1") == 0 {
            statusText = "Installing Ollama via Homebrew..."
            let rc = await runShell("brew install --cask ollama >/dev/null 2>&1 || brew install ollama >/dev/null 2>&1")
            if rc == 0 { return true }
        }

        statusText = "Downloading Ollama for macOS..."
        guard let remote = URL(string: "https://ollama.com/download/Ollama-darwin.zip") else { return false }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OAE-Ollama-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            errorText = "Couldn't create temp folder: \(error.localizedDescription)"
            return false
        }
        let zipDest = tempDir.appendingPathComponent("Ollama-darwin.zip")

        let (tempFile, response): (URL, URLResponse)
        do {
            (tempFile, response) = try await URLSession.shared.download(from: remote)
        } catch {
            errorText = "Couldn't download Ollama (check internet): \(error.localizedDescription)"
            return false
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            errorText = "Couldn't download Ollama (HTTP \(http.statusCode))."
            return false
        }
        do {
            if FileManager.default.fileExists(atPath: zipDest.path) {
                try FileManager.default.removeItem(at: zipDest)
            }
            try FileManager.default.moveItem(at: tempFile, to: zipDest)
        } catch {
            errorText = "Couldn't stage Ollama download: \(error.localizedDescription)"
            return false
        }

        statusText = "Installing Ollama..."
        let extractProc = Process()
        extractProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extractProc.arguments = ["-x", "-k", zipDest.path, tempDir.path]
        do {
            try extractProc.run()
            extractProc.waitUntilExit()
            guard extractProc.terminationStatus == 0 else {
                errorText = "Couldn't unpack Ollama installer."
                return false
            }
        } catch {
            errorText = "Couldn't unpack Ollama installer: \(error.localizedDescription)"
            return false
        }

        let srcApp = tempDir.appendingPathComponent("Ollama.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: srcApp.path) else {
            errorText = "Ollama archive was missing the app bundle."
            return false
        }

        // Prefer /Applications for discoverability. Fall back to ~/Applications (no admin auth needed).
        let systemApps = URL(fileURLWithPath: "/Applications/Ollama.app", isDirectory: true)
        let userApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Ollama.app", isDirectory: true)
        let destApp: URL
        if FileManager.default.isWritableFile(atPath: "/Applications") {
            destApp = systemApps
        } else {
            try? FileManager.default.createDirectory(at: userApps.deletingLastPathComponent(), withIntermediateDirectories: true)
            destApp = userApps
        }
        if FileManager.default.fileExists(atPath: destApp.path) {
            try? FileManager.default.removeItem(at: destApp)
        }
        do {
            try FileManager.default.copyItem(at: srcApp, to: destApp)
        } catch {
            errorText = "Couldn't install Ollama: \(error.localizedDescription)"
            return false
        }
        NSWorkspace.shared.open(destApp)
        return true
    }

    @discardableResult
    private func runShell(_ command: String) async -> Int32 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = ["bash", "-lc", command]
                p.standardOutput = Pipe()
                p.standardError = Pipe()
                do {
                    try p.run()
                    p.waitUntilExit()
                    cont.resume(returning: p.terminationStatus)
                } catch {
                    cont.resume(returning: -1)
                }
            }
        }
    }

    private func isOllamaModelReady(model: String) async -> Bool {
        guard await OllamaBootstrap.ping(nativeRoot: nativeRoot) else { return false }
        guard let url = URL(string: "\(nativeRoot)/api/tags") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = obj["models"] as? [[String: Any]] else { return false }
            let names = models.compactMap { $0["name"] as? String }
            return names.contains { $0 == model || $0.hasPrefix("\(model):") || $0.hasPrefix("\(model)@") }
        } catch {
            return false
        }
    }

    private func pullOllamaModelViaHTTP(model: String) async throws {
        guard let url = URL(string: "\(nativeRoot)/api/pull") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": model, "stream": true])
        req.timeoutInterval = 3600
        let (stream, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "OAE.OllamaPull", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Ollama rejected the pull request (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))."
            ])
        }
        var sawSuccess = false
        for try await line in stream.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let status = obj["status"] as? String {
                statusText = status
                if status == "success" { sawSuccess = true }
            }
            if let total = obj["total"] as? NSNumber,
               let completed = obj["completed"] as? NSNumber,
               total.doubleValue > 0 {
                progress = min(1.0, completed.doubleValue / total.doubleValue)
            }
            if let err = obj["error"] as? String {
                throw NSError(domain: "OAE.OllamaPull", code: 502, userInfo: [NSLocalizedDescriptionKey: err])
            }
        }
        if !sawSuccess {
            throw NSError(domain: "OAE.OllamaPull", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "Ollama pull stream ended without success."
            ])
        }
    }
}

@main
struct OAEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var engine = TranscriptionEngine.shared
    @StateObject private var modelStore: ModelStore
    @StateObject private var hotkeys = HotkeyManager.shared
    @StateObject private var promptLibrary = PromptLibrary.shared
    @StateObject private var transcript = TranscriptStore.shared
    @StateObject private var captureSession = CaptureSessionController()
    @StateObject private var professorSetup: ProfessorSetupCoordinator
    @State private var showProfessorSetupSheet: Bool = false

    init() {
        let store = ModelStore.shared
        _modelStore = StateObject(wrappedValue: store)
        _professorSetup = StateObject(wrappedValue: ProfessorSetupCoordinator(modelStore: store))
    }

    var body: some Scene {
        WindowGroup("OAE") {
            MainWindow()
                .environmentObject(engine)
                .environmentObject(modelStore)
                .environmentObject(hotkeys)
                .environmentObject(promptLibrary)
                .environmentObject(transcript)
                .environmentObject(captureSession)
                .frame(minWidth: 620, minHeight: 520)
                .task {
                    await bootstrap()
                }
                .sheet(isPresented: $showProfessorSetupSheet) {
                    ProfessorSetupSheet(setup: professorSetup)
                }
        }
        .defaultSize(width: 680, height: 570)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(engine)
                .environmentObject(modelStore)
                .environmentObject(hotkeys)
                .environmentObject(promptLibrary)
                .environmentObject(transcript)
                .frame(minWidth: 520, minHeight: 420)
                .frame(idealWidth: 560, idealHeight: 480)
        }
        .defaultSize(width: 560, height: 480)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(engine)
                .environmentObject(transcript)
        } label: {
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor
    private func bootstrap() async {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let exePath = bundle.executableURL?.path ?? "unknown"
        NSLog("[OAE] startup bundle_id=\(bundleID) version=\(version) build=\(build) executable=\(exePath) model_root=\(modelStore.rootURL.path)")

        // Ask for mic permission once at launch, off the blocking semaphore path.
        // If the user already granted it, this is a no-op.
        _ = await AudioCapture.ensureMicPermission()

        // Install the CGEventTap but do NOT force the Accessibility prompt on boot;
        // we surface a "Grant Accessibility" button inside the Capture tab instead.
        hotkeys.install()

        let whisperModel = UserDefaults.standard.string(forKey: SettingsKey.modelName) ?? DefaultModel.name
        let ollamaModel = UserDefaults.standard.string(forKey: SettingsKey.selectedLocalModel) ?? "gemma2:2b"

        // Seed bundled Whisper model BEFORE engine.load so clean installs never
        // trigger an accidental 600 MB network download from HuggingFace.
        if !modelStore.isInstalled(whisperModel) {
            do {
                try modelStore.installBundledModelsIfAvailable(requiredModel: whisperModel)
                NSLog("[OAE] bundled whisper seeded at startup")
            } catch {
                NSLog("[OAE] bundled whisper unavailable at startup (coordinator will handle download): \(error.localizedDescription)")
            }
        }

        // Load the engine only if the model is already on disk. If it isn't, the
        // coordinator below will drive the download and then re-issue the load.
        if modelStore.isInstalled(whisperModel) {
            do {
                try await engine.load(modelName: whisperModel, modelFolder: modelStore.rootURL)
            } catch {
                NSLog("[OAE] model load failed: \(error.localizedDescription)")
            }
        } else {
            NSLog("[OAE] deferring engine load until setup installs the whisper model")
        }

        let needsSetup = await professorSetup.evaluateReadinessOnLaunch(
            requiredWhisper: whisperModel,
            requiredOllamaModel: ollamaModel
        )
        showProfessorSetupSheet = needsSetup
    }
}

private struct ProfessorSetupSheet: View {
    @ObservedObject var setup: ProfessorSetupCoordinator
    @AppStorage(SettingsKey.modelName) private var selectedModel: String = DefaultModel.name
    @AppStorage(SettingsKey.selectedLocalModel) private var selectedLocalModel: String = "gemma2:2b"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preparing OAE for you")
                        .font(.title3.bold())
                    Text("Just a moment — we're getting everything set up automatically.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                stepRow(index: 1,
                        title: "Install transcription model",
                        activeStep: .installingWhisper,
                        nextStep: .installingOllama)
                stepRow(index: 2,
                        title: "Install local AI assistant",
                        activeStep: .installingOllama,
                        nextStep: .startingOllama)
                stepRow(index: 3,
                        title: "Start local AI assistant",
                        activeStep: .startingOllama,
                        nextStep: .pullingOllamaModel)
                stepRow(index: 4,
                        title: "Download local AI model (\(selectedLocalModel))",
                        activeStep: .pullingOllamaModel,
                        nextStep: .done)
            }

            if setup.step != .done && setup.step != .error {
                VStack(alignment: .leading, spacing: 6) {
                    if setup.progress > 0 {
                        ProgressView(value: setup.progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text(setup.statusText.isEmpty ? "Starting up…" : setup.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let err = setup.errorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if setup.step == .error {
                    Button("Skip for now") { dismiss() }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if setup.step == .done {
                    Button("Get started") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else if setup.step == .error {
                    Button("Try again") {
                        Task {
                            await setup.runAutoSetup(
                                requiredWhisper: selectedModel,
                                requiredOllamaModel: selectedLocalModel)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(setup.isWorking)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Working…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .task {
            if !setup.isWorking && setup.step != .done {
                await setup.runAutoSetup(
                    requiredWhisper: selectedModel,
                    requiredOllamaModel: selectedLocalModel)
            }
        }
        .interactiveDismissDisabled(setup.isWorking)
    }

    private func stepRow(index: Int,
                         title: String,
                         activeStep: ProfessorSetupCoordinator.Step,
                         nextStep: ProfessorSetupCoordinator.Step) -> some View {
        let current = setup.step
        let isDone = (current.rawValue >= nextStep.rawValue && current != .error)
            || (current == .error && current.rawValue > activeStep.rawValue)
        let isActive = current == activeStep
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 1.2)
                    .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                } else if isActive {
                    ProgressView().scaleEffect(0.55)
                } else if current == .error && activeStep == stepAtFailure() {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                } else {
                    Text("\(index)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isDone || isActive ? .primary : .secondary)
            Spacer()
        }
    }

    private func stepAtFailure() -> ProfessorSetupCoordinator.Step {
        // When the coordinator transitions into `.error`, `step` already reflects `.error`.
        // We cannot recover which step failed purely from the published state, so we
        // highlight the first non-done step instead by looking at the shipping flags.
        if !UserDefaults.standard.bool(forKey: SettingsKey.shippingModelsReady) { return .installingWhisper }
        if !UserDefaults.standard.bool(forKey: SettingsKey.shippingOllamaReady) {
            return .pullingOllamaModel
        }
        return .done
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private final class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

public final class SubtitleOverlayController: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = SubtitleOverlayController()

    @Published public private(set) var isVisible: Bool = false
    @Published public private(set) var positionLocked: Bool = false

    private var panel: NSPanel?
    private var activeSpaceObserver: Any?
    private var screenParamsObserver: NSObjectProtocol?
    private var lastRefrontAt: Date = .distantPast
    private var didExplicitShow: Bool = false
    private var builtPresentation: SubtitlePresentationMode?
    private let overlayCommandQueue = DispatchQueue(label: "computer.oae.subtitle-overlay-commands")
    private var cachedTranscript: TranscriptStore?

    private enum OverlayCommand {
        case show
        case hide
    }

    private override init() {}

    deinit {
        if let activeSpaceObserver {
            NotificationCenter.default.removeObserver(activeSpaceObserver)
        }
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
        }
    }

    /// Reads `SettingsKey.subtitlePresentation` from UserDefaults.
    public static func currentPresentationMode() -> SubtitlePresentationMode {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.subtitlePresentation)
            ?? SubtitlePresentationMode.floating.rawValue
        return SubtitlePresentationMode(rawValue: raw) ?? .floating
    }

    /// Call after the user changes subtitle presentation in Settings or the main window.
    public func refreshAfterPresentationChange(transcript: TranscriptStore) {
        cachedTranscript = transcript
        overlayCommandQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.applyPresentationChange(transcript: transcript)
            }
        }
    }

    private func readPresentation() -> SubtitlePresentationMode {
        Self.currentPresentationMode()
    }

    private func applyPresentationChange(transcript: TranscriptStore) {
        guard isVisible else { return }
        rebuildPanelKeepingVisibility(transcript: transcript)
    }

    private func rebuildPanelKeepingVisibility(transcript: TranscriptStore) {
        panel?.orderOut(nil)
        panel = nil
        builtPresentation = nil
        showNow(transcript: transcript)
    }

    public func toggle(transcript: TranscriptStore) {
        if isVisible {
            hide()
        } else {
            show(transcript: transcript)
        }
    }

    public func show(transcript: TranscriptStore) {
        cachedTranscript = transcript
        enqueueCommand(.show)
    }

    public func hide() {
        enqueueCommand(.hide)
    }

    public func togglePositionLock() {
        if readPresentation() == .notchStrip { return }
        if safeMode { return }
        positionLocked.toggle()
        applyInteractionMode()
    }

    public func windowWillClose(_ notification: Notification) {
        isVisible = false
    }

    private func ensurePanel(transcript: TranscriptStore) -> NSPanel {
        let mode = readPresentation()
        if let existing = panel, builtPresentation == mode {
            applyChrome(for: mode, to: existing)
            applyInteractionMode()
            if mode == .notchStrip, let screen = NSScreen.main {
                existing.setFrame(Self.computeNotchStripFrame(for: screen), display: true)
            }
            return existing
        }

        if let old = panel {
            old.orderOut(nil)
            self.panel = nil
        }

        let initialRect: NSRect = {
            switch mode {
            case .floating:
                return Self.defaultFloatingFrame()
            case .notchStrip:
                if let screen = NSScreen.main {
                    return Self.computeNotchStripFrame(for: screen)
                }
                return NSRect(x: 220, y: 120, width: 920, height: 68)
            }
        }()

        let style: NSWindow.StyleMask = {
            switch mode {
            case .floating:
                return [.titled, .closable, .fullSizeContentView, .resizable, .nonactivatingPanel]
            case .notchStrip:
                return [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
            }
        }()

        let panel = SubtitlePanel(
            contentRect: initialRect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        applyChrome(for: mode, to: panel)
        // Handy-style safe combo: avoid behaviors that trigger AppKit assertions.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self

        panel.contentView = NSHostingView(
            rootView: SubtitleOverlayView()
                .environmentObject(transcript)
                .environmentObject(self)
        )
        self.panel = panel
        builtPresentation = mode
        applyInteractionMode()
        installSpaceObserver()
        installScreenParametersObserver()
        return panel
    }

    private func applyChrome(for mode: SubtitlePresentationMode, to panel: NSPanel) {
        switch mode {
        case .floating:
            panel.minSize = NSSize(width: 420, height: 96)
            panel.maxSize = NSSize(width: 4000, height: 4000)
        case .notchStrip:
            if let screen = NSScreen.main {
                let r = Self.computeNotchStripFrame(for: screen)
                panel.minSize = NSSize(width: r.width, height: r.height)
                panel.maxSize = panel.minSize
            } else {
                panel.minSize = NSSize(width: 420, height: 68)
                panel.maxSize = panel.minSize
            }
        }
    }

    private static func defaultFloatingFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 220, y: 120, width: 920, height: 140)
        }
        let vf = screen.visibleFrame
        let w: CGFloat = 920
        let h: CGFloat = 140
        let x = vf.minX + (vf.width - w) * 0.5
        let y = vf.minY + (vf.height - h) * 0.35
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// Top-center strip on the menu-bar screen (clean-room; heuristic alignment near camera notch).
    private static func computeNotchStripFrame(for screen: NSScreen) -> NSRect {
        let f = screen.frame
        let w = min(900, max(420, f.width * 0.62))
        let h: CGFloat = 68
        let x = f.minX + (f.width - w) * 0.5
        var topSafe: CGFloat = 0
        if #available(macOS 12.0, *) {
            topSafe = screen.safeAreaInsets.top
        }
        // Sit just below the menu bar / safe inset when the OS reports one; otherwise flush to screen top.
        let y = f.maxY - h - topSafe
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func applyInteractionMode() {
        guard let panel else { return }
        panel.ignoresMouseEvents = false
        switch readPresentation() {
        case .notchStrip:
            panel.isMovableByWindowBackground = false
        case .floating:
            panel.isMovableByWindowBackground = safeMode ? true : !positionLocked
        }
    }

    private func installSpaceObserver() {
        guard activeSpaceObserver == nil else { return }
        activeSpaceObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let panel = self.panel, self.isVisible else { return }
            guard self.didExplicitShow else { return }
            if self.readPresentation() == .notchStrip, let screen = NSScreen.main {
                panel.setFrame(Self.computeNotchStripFrame(for: screen), display: true)
            }
            // Re-front only when it lost visibility on a space transition.
            guard !panel.occlusionState.contains(.visible) else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastRefrontAt) > 0.6 else { return }
            self.lastRefrontAt = now
            panel.orderFrontRegardless()
            NSLog("[OAE.Subtitles] refront_on_space_change")
        }
    }

    private func installScreenParametersObserver() {
        guard screenParamsObserver == nil else { return }
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reframeNotchStripIfNeeded()
        }
    }

    private func reframeNotchStripIfNeeded() {
        guard isVisible, readPresentation() == .notchStrip, let panel, let screen = NSScreen.main else { return }
        let r = Self.computeNotchStripFrame(for: screen)
        panel.minSize = NSSize(width: r.width, height: r.height)
        panel.maxSize = panel.minSize
        panel.setFrame(r, display: true)
        NSLog("[OAE.Subtitles] reframe_notch_strip")
    }

    private var safeMode: Bool {
        UserDefaults.standard.bool(forKey: "oae.subtitle.safeMode")
    }

    private func enqueueCommand(_ command: OverlayCommand) {
        overlayCommandQueue.async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.apply(command)
            }
        }
    }

    private func apply(_ command: OverlayCommand) {
        switch command {
        case .show:
            guard !isVisible else { return }
            guard let transcript = cachedTranscript else { return }
            showNow(transcript: transcript)
        case .hide:
            guard isVisible else { return }
            hideNow()
        }
    }

    private func showNow(transcript: TranscriptStore) {
        let panel = ensurePanel(transcript: transcript)
        panel.ignoresMouseEvents = false
        if readPresentation() == .notchStrip, let screen = NSScreen.main {
            let r = Self.computeNotchStripFrame(for: screen)
            panel.minSize = NSSize(width: r.width, height: r.height)
            panel.maxSize = panel.minSize
            panel.setFrame(r, display: true)
        }
        panel.orderFront(nil)
        isVisible = true
        didExplicitShow = true
        NSLog("[OAE.Subtitles] show level=\(panel.level.rawValue) mode=\(readPresentation().rawValue) locked=\(positionLocked)")
    }

    private func hideNow() {
        panel?.orderOut(nil)
        isVisible = false
        didExplicitShow = false
        NSLog("[OAE.Subtitles] hide")
    }
}

public struct SubtitleOverlayView: View {
    @EnvironmentObject var transcript: TranscriptStore
    @EnvironmentObject var overlay: SubtitleOverlayController

    @AppStorage("oae.subtitle.fontSize") private var fontSize: Double = 35
    @AppStorage("oae.subtitle.backgroundOpacity") private var bgOpacity: Double = 0.62
    /// Segmented control: 3 = 12 words, 5 = 15 words, 7 = 18 words (fixed island capacity).
    @AppStorage("oae.subtitle.chunkWords") private var chunkWords: Int = 5
    @AppStorage("oae.subtitle.safeMode") private var safeMode: Bool = true
    @AppStorage(SettingsKey.subtitlePresentation) private var presentationRaw: String = SubtitlePresentationMode.floating.rawValue
    @State private var controlsVisible: Bool = false
    @State private var ring = SubtitleIslandRingViewport(capacity: 15)
    @State private var islandSlots: [String] = []

    private var presentation: SubtitlePresentationMode {
        SubtitlePresentationMode(rawValue: presentationRaw) ?? .floating
    }

    /// Island shows exactly this many word slots (leading slots may be empty until filled).
    private var islandWordCapacity: Int {
        switch chunkWords {
        case 3: return 12
        case 5: return 15
        case 7: return 18
        default: return 15
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            if controlsVisible {
                HStack(spacing: 10) {
                    Image(systemName: presentation == .notchStrip ? "platter.top.filled.iphone" : "line.3.horizontal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(presentation == .notchStrip ? "Pinned below menu bar" : "Drag here to move")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer()
                    Label("Subtitles", systemImage: "captions.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.1))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Keep island display-only (Handy-style) to avoid gesture callback crashes.
            // Fixed-slot ring + per-word layout reduces reflow when Whisper revises the tail.
            Group {
                if islandSlots.isEmpty || islandSlots.allSatisfy({ $0.isEmpty }) {
                    Text("Your live subtitles will appear here...")
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 6) {
                        islandSlotRow(Array(islandSlots.prefix(min(8, islandSlots.count))), baseIndex: 0)
                        if islandSlots.count > 8 {
                            islandSlotRow(Array(islandSlots.dropFirst(8)), baseIndex: 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
            }
            .minimumScaleFactor(0.72)
            .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 1)

            if controlsVisible {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Size")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: $fontSize, in: 24...54, step: 1)
                    }
                    HStack(spacing: 6) {
                        Text("BG")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: $bgOpacity, in: 0.2...0.85, step: 0.01)
                    }
                    Picker("Chunk", selection: $chunkWords) {
                        Text("12w").tag(3)
                        Text("15w").tag(5)
                        Text("18w").tag(7)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 118)
                    .accessibilityLabel("Subtitle word capacity")
                    .help("Maximum words on the island at once (12 / 15 / 18). Oldest word drops when you add a new one; rewrites patch only the unstable prefix so the tail does not jump as much.")
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(bgOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                controlsVisible.toggle()
            }
        }
        .padding(10)
        .onAppear {
            ring = SubtitleIslandRingViewport(capacity: islandWordCapacity)
            syncIslandSlots()
        }
        .onChange(of: transcript.fullText) { _, _ in syncIslandSlots() }
        .onChange(of: transcript.confirmedSegments.count) { _, _ in syncIslandSlots() }
        .onChange(of: chunkWords) { _, _ in
            ring = SubtitleIslandRingViewport(capacity: islandWordCapacity)
            syncIslandSlots()
        }
    }

    @ViewBuilder
    private func islandSlotRow(_ words: [String], baseIndex: Int) -> some View {
        let minCell = max(22, fontSize * 0.4)
        HStack(spacing: 5) {
            ForEach(words.indices.map { baseIndex + $0 }, id: \.self) { globalIdx in
                let local = globalIdx - baseIndex
                let word = words[local]
                let isEmpty = word.trimmingCharacters(in: .whitespaces).isEmpty
                Text(isEmpty ? "\u{00a0}" : word)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(isEmpty ? .clear : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: isEmpty ? 3 : minCell)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func syncIslandSlots() {
        let base = transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            ring.reset()
            islandSlots = []
            return
        }
        let words = tokenize(base)
        var r = ring
        islandSlots = r.apply(allWords: words)
        ring = r
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}
