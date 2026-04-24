import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct FileView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @EnvironmentObject var transcript: TranscriptStore

    @AppStorage(SettingsKey.language) private var languageRaw: String = TranscriptionLanguage.auto.rawValue

    @State private var droppedURL: URL?
    @State private var progress: Double = 0
    @State private var stage: String = "Drop an audio or video file"
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var isTargeted = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                dropZone
                    .padding(.horizontal)

                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.25))
                    TranscriptView(showTimestamps: true)
                }
                .padding(.horizontal)

                HStack {
                    if isWorking {
                        ProgressView(value: progress)
                            .frame(maxWidth: 220)
                        Text(stage).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(ExportFormat.allCases) { fmt in
                            Button(fmt.displayName) { export(format: fmt) }
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(transcript.confirmedSegments.isEmpty)
                    Button {
                        Clipboard.copy(transcript.fullText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(transcript.fullText.isEmpty)
                }
                .padding(.horizontal)

                if let e = errorText {
                    Text(e).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
        .onAppear {
            transcript.activate(source: .file)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("File").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Drop any audio or video. Live partials while decoding, canonical text at the end.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose File…", action: openPicker)
        }
        .padding(.horizontal)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            VStack(spacing: 8) {
                Image(systemName: droppedURL == nil ? "square.and.arrow.down" : "waveform")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(droppedURL?.lastPathComponent ?? "Drop .wav .mp3 .m4a .mp4 .mkv .webm …")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Text(droppedURL == nil ? "or click Choose File…" : "Click Start to transcribe")
                    .font(.caption).foregroundStyle(.secondary)
                if droppedURL != nil {
                    Button {
                        if let u = droppedURL { run(url: u) }
                    } label: {
                        Label("Transcribe", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                }
            }
        }
        .frame(height: 140)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let u = url {
                DispatchQueue.main.async {
                    self.droppedURL = u
                    self.run(url: u)
                }
            }
        }
        return true
    }

    private func openPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = FileImportService.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            self.droppedURL = url
            self.run(url: url)
        }
    }

    private func run(url: URL) {
        guard !isWorking else { return }
        Task {
            isWorking = true
            stage = "Decoding…"
            progress = 0
            errorText = nil
            transcript.reset(source: .file)
            defer { isWorking = false; progress = 1 }

            do {
                let importer = FileImportService()

                // Pass 1 — streaming preview while decoding.
                let handle = try importer.stream(url: url)
                var buf: [Float] = []
                var totalSeen: Int64 = 0
                let total = handle.totalFrameEstimate ?? 0
                for try await chunk in handle.samples {
                    buf.append(contentsOf: chunk)
                    totalSeen += Int64(chunk.count)
                    if total > 0 { progress = min(0.5, Double(totalSeen) / Double(total) * 0.5) }
                    let secs = Float(buf.count) / 16_000
                    transcript.updateFilePartial("Decoded \(String(format: "%.1f", secs)) s…")
                }

                // Pass 2 — final high-quality single-shot transcription over the full buffer.
                stage = "Transcribing…"
                let lang = TranscriptionLanguage(rawValue: languageRaw)?.whisperCode
                let (_, segments) = try await engine.transcribeFile(at: url, language: lang)
                transcript.replaceConfirmed(with: segments)
                progress = 1
                stage = "Done"
            } catch {
                errorText = error.localizedDescription
                stage = "Error"
            }
        }
    }

    private func export(format: ExportFormat) {
        let content = TranscriptExporter.render(segments: transcript.confirmedSegments,
                                                fullText: transcript.fullText,
                                                format: format)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (droppedURL?.deletingPathExtension().lastPathComponent ?? "transcript") + "." + format.fileExtension
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.data(using: .utf8)?.write(to: url)
        }
    }
}
