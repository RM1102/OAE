import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif

public enum MainTab: String, CaseIterable, Identifiable {
    case dictate, capture, file, post
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dictate: return "Dictate"
        case .capture: return "Capture"
        case .file:    return "File"
        case .post:    return "Post Process"
        }
    }
    public var symbol: String {
        switch self {
        case .dictate: return "waveform"
        case .capture: return "record.circle"
        case .file:    return "doc.text.fill"
        case .post:    return "sparkles"
        }
    }
}

public struct MainWindow: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @EnvironmentObject var hotkeys: HotkeyManager
    @EnvironmentObject var transcript: TranscriptStore
    @EnvironmentObject var promptLibrary: PromptLibrary
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var captureSession: CaptureSessionController

    @State private var selection: MainTab = .dictate
    @State private var previousNonPostSelection: MainTab = .dictate
    @AppStorage("oae.onboarded.firstRun") private var firstRunOnboarded: Bool = false
    @AppStorage("oae.subtitle.safeMode") private var subtitleSafeMode: Bool = true
    @AppStorage(SettingsKey.subtitlePresentation) private var subtitlePresentationRaw: String = SubtitlePresentationMode.floating.rawValue
    @State private var showFirstRunSheet: Bool = false
    @State private var subtitlesVisible: Bool = false
    @State private var subtitleLocked: Bool = false

    private var subtitlePresentationMode: SubtitlePresentationMode {
        SubtitlePresentationMode(rawValue: subtitlePresentationRaw) ?? .floating
    }

    public init() {}

    private let sidebarWidth: CGFloat = 152

    public var body: some View {
        HStack(spacing: 0) {
            mainSidebar
            Divider()
            VStack(spacing: 0) {
                detailTopBar
                engineBanner
                Group {
                    switch selection {
                    case .dictate: DictateView()
                    case .capture: CaptureView()
                    case .file:    FileView()
                    case .post:    PostProcessView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
            .frame(minWidth: 0, minHeight: 0)
        }
        .padding(.top, 10)
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
        .onReceive(hotkeys.events) { ev in
            switch ev {
            case .postProcess:
                if selection != .post {
                    previousNonPostSelection = selection
                }
                selection = .post
            case .pttStart:
                captureSession.startRecording(transcript: transcript)
            case .pttStop:
                captureSession.stopAndTranscribe(engine: engine, transcript: transcript)
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue != .post {
                previousNonPostSelection = newValue
            }
        }
        .onChange(of: subtitlePresentationRaw) { _, _ in
            SubtitleOverlayController.shared.refreshAfterPresentationChange(transcript: transcript)
        }
        .onAppear {
            showFirstRunSheet = !firstRunOnboarded
            subtitlesVisible = SubtitleOverlayController.shared.isVisible
            subtitleLocked = SubtitleOverlayController.shared.positionLocked
        }
        .onReceive(SubtitleOverlayController.shared.$isVisible) { subtitlesVisible = $0 }
        .onReceive(SubtitleOverlayController.shared.$positionLocked) { subtitleLocked = $0 }
        .sheet(isPresented: $showFirstRunSheet) {
            firstRunSheet
        }
    }

    private var mainSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                OAELogoMark(size: 22)
                Text("OAE")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(MainTab.allCases) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)

            Spacer(minLength: 0)

            Text(engine.currentModelName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
        }
        .frame(width: sidebarWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
    }

    private func sidebarRow(_ tab: MainTab) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18, alignment: .center)
                Text(tab.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.22))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : .primary)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var detailTopBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if selection == .post {
                Button {
                    selection = previousNonPostSelection
                } label: {
                    Label("Back", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .lineLimit(1)
            }
            Button {
                SubtitleOverlayController.shared.toggle(transcript: transcript)
            } label: {
                Label(subtitlesVisible ? "Close subtitles" : "Open subtitles",
                      systemImage: subtitlesVisible ? "xmark.circle.fill" : "captions.bubble.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(subtitlesVisible ? .red : .blue)
            .lineLimit(1)
            Picker("Subtitle layout", selection: $subtitlePresentationRaw) {
                ForEach(SubtitlePresentationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .labelsHidden()
            .accessibilityLabel("Subtitle layout")
            .help("Floating island: drag anywhere. Top notch strip: pinned under the menu bar.")
            if subtitlesVisible {
                Toggle("Safe", isOn: $subtitleSafeMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Safe mode uses a minimal, more reliable subtitle island.")
                if !subtitleSafeMode, subtitlePresentationMode != .notchStrip {
                    Button {
                        SubtitleOverlayController.shared.togglePositionLock()
                    } label: {
                        Label(subtitleLocked ? "Unlock Move" : "Lock Position",
                              systemImage: subtitleLocked ? "lock.fill" : "lock.open")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            LocalOllamaReadinessPill()
            StatusPill()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var engineBanner: some View {
        if engine.isLoading {
            loadingBanner
        } else if engine.whisperKit == nil {
            notLoadedBanner
        }
    }

    private var loadingBanner: some View {
        HStack(spacing: 10) {
            ProgressView(value: engine.loadProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 220)
            Text(engine.loadProgress > 0
                 ? "Downloading \(engine.currentModelName) · \(Int(engine.loadProgress * 100))%"
                 : "Preparing \(engine.currentModelName)…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private var notLoadedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.lastError ?? "The transcription model is not loaded yet.")
                    .font(.caption).lineLimit(2)
                Text("Nothing will transcribe until the model finishes loading.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    try? await engine.load(modelName: engine.currentModelName, modelFolder: modelStore.rootURL)
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.08))
    }

    private var firstRunSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to OAE").font(.title2.bold())
            Text("Quick first-run checklist for clean demos on new MacBooks.")
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: engine.whisperKit == nil ? "arrow.down.circle" : "checkmark.circle.fill")
                    .foregroundStyle(engine.whisperKit == nil ? .orange : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model download").font(.headline)
                    if engine.isLoading {
                        Text("Downloading \(Int(engine.loadProgress * 100))%…").font(.caption).foregroundStyle(.secondary)
                    } else if engine.whisperKit != nil {
                        Text("Loaded: \(engine.currentModelName)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Will auto-download and load on first run").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack {
                Image(systemName: hotkeys.trustGranted ? "checkmark.circle.fill" : "hand.raised")
                    .foregroundStyle(hotkeys.trustGranted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility (for Capture hotkeys)").font(.headline)
                    Text("Open Capture tab and click Grant Accessibility if needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Image(systemName: "mic")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone").font(.headline)
                    Text("macOS prompts on first use in Dictate/Capture.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            HStack {
                Spacer()
                Button("Open Capture Tab") {
                    selection = .capture
                }
                .buttonStyle(.bordered)
                Button("Done") {
                    firstRunOnboarded = true
                    showFirstRunSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

/// Compact logo for the window title bar: prefers the asset catalog `AppIcon`
/// (same OAE artwork as Dock / Finder) and falls back to a gradient + "OAE" label
/// if the image is missing.
public struct OAELogoMark: View {
    let size: CGFloat
    public init(size: CGFloat = 22) { self.size = size }

    public var body: some View {
        Group {
            #if os(macOS)
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackLogo
            }
            #else
            fallbackLogo
            #endif
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    private var fallbackLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.96, green: 0.31, blue: 0.62),
                                 Color(red: 0.60, green: 0.24, blue: 0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("OAE")
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .kerning(-0.4)
        }
    }
}
