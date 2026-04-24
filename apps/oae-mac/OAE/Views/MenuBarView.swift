import SwiftUI
import AppKit

public struct MenuBarView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @EnvironmentObject var transcript: TranscriptStore
    @AppStorage(SettingsKey.subtitlePresentation) private var subtitlePresentationRaw: String = SubtitlePresentationMode.floating.rawValue
    @State private var subtitlesVisible: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OAE").font(.headline)
                    Text(engine.acceleration.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()

            Button {
                openMainWindow()
            } label: {
                Label("Show OAE", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            if !transcript.fullText.isEmpty {
                Button {
                    Clipboard.copy(transcript.fullText)
                } label: {
                    Label("Copy last transcript", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
            }

            Button {
                if subtitlesVisible {
                    SubtitleOverlayController.shared.hide()
                } else {
                    SubtitleOverlayController.shared.show(transcript: transcript)
                }
            } label: {
                Label(subtitlesVisible ? "Close live subtitles" : "Open live subtitles",
                      systemImage: subtitlesVisible ? "xmark.circle.fill" : "captions.bubble.fill")
            }
            .buttonStyle(.plain)

            Picker("Layout", selection: $subtitlePresentationRaw) {
                ForEach(SubtitlePresentationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: subtitlePresentationRaw) { _, _ in
                SubtitleOverlayController.shared.refreshAfterPresentationChange(transcript: transcript)
            }

            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            subtitlesVisible = SubtitleOverlayController.shared.isVisible
        }
        .onReceive(SubtitleOverlayController.shared.$isVisible) { subtitlesVisible = $0 }
    }

    private func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "OAE" }) ??
            NSApp.windows.first(where: { $0.contentViewController != nil }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
