import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, models, shortcuts, prompts, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .models: return "Models"
        case .shortcuts: return "Shortcuts"
        case .prompts: return "Prompts"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gear"
        case .models: return "brain"
        case .shortcuts: return "keyboard"
        case .prompts: return "text.book.closed"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var hotkeys: HotkeyManager
    @EnvironmentObject var promptLibrary: PromptLibrary
    @EnvironmentObject var transcript: TranscriptStore
    @EnvironmentObject var updateService: UpdateService

    @State private var section: SettingsSection = .general

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SettingsSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 124, ideal: 144, max: 168)
        } detail: {
            ScrollView {
                Group {
                    switch section {
                    case .general: GeneralTab()
                    case .models: ModelsTab()
                    case .shortcuts: ShortcutsTab()
                    case .prompts: PromptsTab()
                    case .updates: UpdatesTab()
                    case .about: AboutTab()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var transcript: TranscriptStore
    @AppStorage(SettingsKey.language) var languageRaw: String = TranscriptionLanguage.auto.rawValue
    @AppStorage(SettingsKey.autoCopy) var autoCopy: Bool = true
    @AppStorage(SettingsKey.autoPaste) var autoPaste: Bool = false
    @AppStorage(SettingsKey.confirmationSegments) var confirmationSegments: Int = 2
    @AppStorage(SettingsKey.lowLatencyLive) var lowLatencyLive: Bool = true
    @AppStorage(SettingsKey.liveStreamingPreset) var liveStreamingPresetRaw: String = LiveStreamer.StreamingPreset.ultraLowLatency.rawValue
    @AppStorage(SettingsKey.dictateRewriteLookbackWords) var rewriteLookbackWords: Int = 10
    @AppStorage(SettingsKey.subtitlePresentation) var subtitlePresentationRaw: String = SubtitlePresentationMode.floating.rawValue
    @AppStorage(SettingsKey.subtitleMovieInsetFromBottom) var subtitleMovieInsetFromBottom: Double = 60
    @AppStorage(SettingsKey.subtitleMovieMaxWidthFraction) var subtitleMovieMaxWidthFraction: Double = 0.72
    @AppStorage(SettingsKey.subtitleMovieHorizontalBias) var subtitleMovieHorizontalBias: Double = 0
    @AppStorage(SettingsKey.subtitleCaptionStyle) var subtitleCaptionStyleRaw: String = SubtitleCaptionStyle.classicStable.rawValue
    @AppStorage(SettingsKey.subtitleIslandMonospace) var subtitleIslandMonospace: Bool = false
    @AppStorage(SettingsKey.subtitlePaceMode) var subtitlePaceModeRaw: String = SubtitlePaceMode.lectureStable.rawValue

    private var subtitlePresentation: SubtitlePresentationMode {
        SubtitlePresentationMode(rawValue: subtitlePresentationRaw) ?? .floating
    }

    var body: some View {
        Form {
            Picker("Language", selection: $languageRaw) {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            Toggle("Copy to clipboard on Stop (push-to-talk)", isOn: $autoCopy)
            Toggle("Auto-paste into front app (requires Accessibility)", isOn: $autoPaste)
            Toggle("Low latency live confirmation", isOn: $lowLatencyLive)
            Picker("Live subtitle mode", selection: $liveStreamingPresetRaw) {
                ForEach(LiveStreamer.StreamingPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            Stepper(value: $rewriteLookbackWords, in: 6...18) {
                HStack { Text("Rewrite lookback words"); Spacer(); Text("\(rewriteLookbackWords)") }
            }
            .help("When Whisper revises recent words, OAE can rewrite trailing words in the saved transcript. The subtitle island reads a separate confirmed/volatile feed and keeps confirmed text visually anchored.")
            Picker("Live subtitle layout", selection: $subtitlePresentationRaw) {
                ForEach(SubtitlePresentationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .onChange(of: subtitlePresentationRaw) { _, _ in
                SubtitleOverlayController.shared.refreshAfterPresentationChange(transcript: transcript)
            }
            if subtitlePresentation == .movie {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Movie: distance from bottom")
                        Spacer()
                        Text("\(Int(subtitleMovieInsetFromBottom)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $subtitleMovieInsetFromBottom, in: 24...140, step: 2)
                    HStack {
                        Text("Movie: max line width")
                        Spacer()
                        Text("\(Int(subtitleMovieMaxWidthFraction * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $subtitleMovieMaxWidthFraction, in: 0.5...0.92, step: 0.02)
                    HStack {
                        Text("Movie: horizontal nudge")
                        Spacer()
                        Text("\(Int(subtitleMovieHorizontalBias)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $subtitleMovieHorizontalBias, in: -200...200, step: 2)
                }
                Text("Movie mode uses a full-screen clear panel with a small black caption block; clicks pass through. Adjust placement here (not while dragging a floating island).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Subtitle caption style", selection: $subtitleCaptionStyleRaw) {
                ForEach(SubtitleCaptionStyle.allCases) { style in
                    Text(style.displayName).tag(style.rawValue)
                }
            }
            .help("Classic stable uses one caption line with an adaptive 7/8 word window and separate pacing for volatile gray tail vs line rolls.")
            Picker("Subtitle pace", selection: $subtitlePaceModeRaw) {
                ForEach(SubtitlePaceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .help("Lecture (stable) is the default: slower cadence, one-line captions (~7 words, auto-expanding to 8 when speech is fast), and spacing between confirm vs roll updates for readability. Realtime (faster) tightens those timings.")
            Toggle("Subtitle island: stable metrics (monospace)", isOn: $subtitleIslandMonospace)
                .help("Optional advanced mode for maximum visual stability. Uses monospaced glyph metrics in the subtitle island.")
            Text("Layouts: floating island (draggable), top notch strip, or movie-style lower-third block. Classic stable shows one caption line with dim volatile tail and confirmed words in full opacity.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper(value: $confirmationSegments, in: 1...4) {
                HStack { Text("Confirmation segments"); Spacer(); Text("\(confirmationSegments)") }
            }
            Text("LocalAgreement confirmation controls when gray pending text turns white. Low latency mode forces faster confirmation (fewer segments), with slightly higher chance of micro-corrections.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Models

private struct ModelsTab: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @EnvironmentObject var store: ModelStore
    @AppStorage(SettingsKey.modelName) var selected: String = DefaultModel.name

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Models").font(.headline)
            ForEach(store.models, id: \.id) { m in
                modelRow(m)
            }
            if store.isDownloading {
                ProgressView(value: store.downloadProgress) {
                    Text("Downloading \(store.activeDownload ?? "")…").font(.caption)
                }
            }
            Text("Models are stored at \(store.rootURL.path).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func modelRow(_ m: AvailableModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        if m.installed {
                            Label("Installed", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if selected == m.id {
                            Text("Active").font(.caption).foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(m.notes).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(m.sizeLabel).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if !m.installed {
                    Button("Download") {
                        Task { try? await store.download(m.id) }
                    }
                    .disabled(store.isDownloading)
                } else {
                    Button("Use") {
                        selected = m.id
                        Task { try? await engine.load(modelName: m.id, modelFolder: store.rootURL) }
                    }
                    .disabled(selected == m.id)
                    Button(role: .destructive) {
                        try? store.delete(m.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selected == m.id)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.25)))
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @EnvironmentObject var hotkeys: HotkeyManager

    var body: some View {
        Form {
            Section("Push-to-talk") {
                HStack {
                    Text("Right Option (⌥R)")
                    Spacer()
                    Text("Start recording").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Left Option (⌥L)")
                    Spacer()
                    Text("Stop & transcribe").foregroundStyle(.secondary)
                }
            }
            Section("Post Process") {
                HStack {
                    Text("⌥⇧Space")
                    Spacer()
                    Text("Run selected prompt on last transcript").foregroundStyle(.secondary)
                }
            }
            Section("Accessibility") {
                HStack {
                    if hotkeys.trustGranted {
                        Label("Accessibility granted", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Label("Accessibility required", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Spacer()
                        Button("Grant") { _ = hotkeys.checkTrust(prompt: true) }
                    }
                }
                Text("OAE needs Accessibility permission to detect the left vs right Option key (via CGEventTap) and to auto-paste transcripts into other apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Prompts

private struct PromptsTab: View {
    @EnvironmentObject var library: PromptLibrary
    @State private var editing: PromptTemplate?
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Prompts").font(.headline)
                Spacer()
                Button {
                    isCreating = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .help("Create New Prompt")
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(library.prompts) { p in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(p.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                                    if p.isBuiltin {
                                        Text("built-in").font(.caption2).foregroundStyle(.secondary)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                                    }
                                }
                                Text(p.user.replacingOccurrences(of: "{{transcript}}", with: "…"))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                        }
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Button("Duplicate") { library.duplicate(p) }
                            if !p.isBuiltin {
                                Button("Edit") { editing = p }
                                Button(role: .destructive) { library.remove(p.id) } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
            }
        }
        .sheet(item: $editing) { p in
            PromptEditorView(template: p).environmentObject(library)
        }
        .sheet(isPresented: $isCreating) {
            PromptEditorView().environmentObject(library)
        }
    }
}

// MARK: - Updates

private struct UpdatesTab: View {
    @EnvironmentObject var updateService: UpdateService
    @AppStorage(SettingsKey.updatesWantsBeta) private var wantsBeta: Bool = false
    @State private var autoCheck: Bool = true
    @State private var showAllVersions = false
    @State private var catalog: [UpdateService.AppcastCatalogEntry] = []
    @State private var catalogLoading = false
    @State private var catalogError: String?

    var body: some View {
        Form {
            Section("In-app updates") {
                Toggle("Automatically check for updates", isOn: $autoCheck)
                    .onChange(of: autoCheck) { _, v in
                        updateService.automaticallyChecksForUpdates = v
                    }
                Toggle("Receive beta updates", isOn: $wantsBeta)
                    .onChange(of: wantsBeta) { _, _ in
                        updateService.applyBetaChannelChange()
                    }
                Button("Check for Updates Now…") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
            }
            Section("All releases") {
                Button("Show all versions…") {
                    showAllVersions = true
                }
                Text("Lists every DMG published in the update feed. Sparkle installs the newest compatible build automatically; use Download for a specific older or beta DMG.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            autoCheck = updateService.automaticallyChecksForUpdates
        }
        .sheet(isPresented: $showAllVersions) {
            AppcastCatalogSheet(
                catalog: $catalog,
                loading: $catalogLoading,
                errorText: $catalogError,
                updateService: updateService
            )
            .frame(minWidth: 420, minHeight: 360)
        }
    }
}

private struct AppcastCatalogSheet: View {
    @Binding var catalog: [UpdateService.AppcastCatalogEntry]
    @Binding var loading: Bool
    @Binding var errorText: String?
    var updateService: UpdateService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading catalog…")
                } else if let err = errorText {
                    Text(err).foregroundStyle(.red)
                } else if catalog.isEmpty {
                    Text("No releases found in the feed yet.")
                        .foregroundStyle(.secondary)
                } else {
                    List(catalog) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.title).font(.headline)
                                Spacer()
                                if let ch = row.channel {
                                    Text(ch)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                                }
                            }
                            Text("Build \(row.versionString) · \(row.displayVersionString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if row.isSameAsHost {
                                Text("This build")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else if row.isNewerThanHost {
                                Text("Newer than installed")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            if let url = row.downloadURL {
                                Button("Download DMG…") {
                                    updateService.openDownloadURL(url)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(16)
            .navigationTitle("All versions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                loading = true
                errorText = nil
                defer { loading = false }
                do {
                    catalog = try await updateService.fetchAppcastCatalog()
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    @EnvironmentObject var engine: TranscriptionEngine
    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OAE").font(.largeTitle.bold())
            Text("Office of Diversity and Inclusion · macOS dictation").foregroundStyle(.secondary)
            Divider()
            KV("Engine", "WhisperKit")
            KV("Acceleration", engine.acceleration.rawValue)
            KV("Active model", engine.currentModelName)
            KV("Version", appVersion)
            KV("Bundle ID", Bundle.main.bundleIdentifier ?? "unknown")
            KV("Executable", Bundle.main.executableURL?.path ?? "unknown")
            Divider()
            Text("Whisper audio encoder and text decoder run on the Apple Neural Engine; mel spectrogram runs on the GPU. The CPU handles only audio I/O and UI.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return "\(short) (\(build))"
    }

    private func KV(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.system(.body, design: .monospaced))
        }
    }
}
