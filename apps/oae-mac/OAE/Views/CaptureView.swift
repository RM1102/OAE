import SwiftUI
import AppKit

public struct CaptureView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @EnvironmentObject var hotkeys: HotkeyManager
    @EnvironmentObject var transcript: TranscriptStore
    @EnvironmentObject var captureSession: CaptureSessionController

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(captureSession.capture.isRecording ? Color.red.opacity(0.9) : Color.secondary.opacity(0.3),
                                    lineWidth: captureSession.capture.isRecording ? 6 : 3)
                            .frame(width: 160, height: 160)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                       value: captureSession.capture.isRecording)
                        Image(systemName: captureSession.capture.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(captureSession.capture.isRecording ? .red : .secondary)
                    }
                    Text(captureSession.statusLine)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

                WaveformView(levels: captureSession.capture.levels, active: captureSession.capture.isRecording)
                    .frame(height: 54)
                    .padding(.horizontal, 20)

                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.25))
                    TranscriptView()
                }
                .padding(.horizontal)

                HStack {
                    keyTip
                    Spacer()
                    Button {
                        Clipboard.copy(transcript.fullText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(transcript.fullText.isEmpty)
                }
                .padding(.horizontal)

                if let e = captureSession.errorText {
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
            transcript.activate(source: .capture)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Push-to-talk").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Right Option to start, left Option to stop + transcribe + copy.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !hotkeys.trustGranted {
                Button {
                    _ = hotkeys.checkTrust(prompt: true)
                } label: {
                    Label("Grant Accessibility", systemImage: "lock.shield")
                }
            }
            Button {
                captureSession.capture.isRecording
                    ? captureSession.stopAndTranscribe(engine: engine, transcript: transcript)
                    : captureSession.startRecording(transcript: transcript)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: captureSession.capture.isRecording ? "stop.circle.fill" : "record.circle.fill")
                    Text(captureSession.capture.isRecording ? "Stop" : "Start")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(captureSession.capture.isRecording ? .red : .accentColor)
            .disabled(!captureSession.capture.isRecording && (engine.whisperKit == nil || engine.isLoading))
        }
        .padding(.horizontal)
    }

    private var keyTip: some View {
        HStack(spacing: 6) {
            keyCap("R ⌥"); Text("start")
            Text("·").foregroundStyle(.tertiary)
            keyCap("⌥ L"); Text("stop + transcribe")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func keyCap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
    }
}
