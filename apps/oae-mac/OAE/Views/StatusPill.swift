import SwiftUI

public struct StatusPill: View {
    @EnvironmentObject var engine: TranscriptionEngine

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .help(tooltip)
    }

    private var label: String {
        if engine.isLoading {
            return "Loading · \(Int(engine.loadProgress * 100))%"
        }
        if engine.whisperKit == nil {
            return engine.lastError == nil ? "Not loaded" : "Load failed"
        }
        return engine.acceleration.rawValue
    }
    private var dotColor: Color {
        if engine.isLoading { return .yellow }
        if engine.whisperKit == nil { return .red }
        switch engine.acceleration {
        case .aneAndGPU: return .green
        case .gpuOnly:   return .orange
        case .cpuFallback: return .red
        }
    }
    private var tooltip: String {
        if engine.isLoading {
            return "Downloading / loading model \(engine.currentModelName)…"
        }
        if engine.whisperKit == nil {
            return engine.lastError ?? "Model not loaded yet."
        }
        switch engine.acceleration {
        case .aneAndGPU: return "Whisper runs on the Apple Neural Engine (encoder + decoder) and GPU (mel spectrogram). CPU handles only audio I/O and UI."
        case .gpuOnly:   return "Neural Engine not available. Running on GPU. Still no model math on CPU cores."
        case .cpuFallback: return "CPU fallback — this app refuses to run in this state."
        }
    }
}

// MARK: - Local Ollama / Gemma (post-process)

/// Shows whether the local Ollama endpoint and pulled model (e.g. Gemma) are reachable for Post Process.
public struct LocalOllamaReadinessPill: View {
    @AppStorage(SettingsKey.selectedProvider) private var providerId: String = ProviderRegistry.defaultProviderId
    @AppStorage(SettingsKey.selectedLocalModel) private var localModel: String = "gemma2:2b"

    @State private var phase: OllamaPhase = .idle

    private enum OllamaPhase: Equatable {
        case idle
        case checking
        case ready
        case failed(String)
    }

    public init() {}

    public var body: some View {
        Group {
            if providerId == "local-ollama" {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                    Text(shortLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 999)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .help(helpText)
                .task(id: localModel) { await pollOllamaLoop() }
            }
        }
    }

    private var shortLabel: String {
        if localModel.lowercased().contains("gemma") { return "Gemma" }
        if localModel.split(separator: ":").first.map(String.init)?.count ?? 0 > 12 {
            return "Ollama"
        }
        return localModel.split(separator: "/").last.map(String.init) ?? "Ollama"
    }

    private var dotColor: Color {
        switch phase {
        case .idle, .checking: return .yellow
        case .ready: return .green
        case .failed: return .red
        }
    }

    private var helpText: String {
        let base = ProviderRegistry.preset(id: "local-ollama")?.baseURL ?? "http://127.0.0.1:11434"
        switch phase {
        case .idle, .checking:
            return "Checking Ollama at \(base) for model \(localModel)…"
        case .ready:
            return "Ollama is running and model \(localModel) is available. Post Process (local) can run."
        case .failed(let msg):
            return msg
        }
    }

    @MainActor
    private func refreshOnce() async {
        phase = .checking
        let config = ProviderUserConfig(presetId: "local-ollama", model: localModel, baseURLOverride: nil)
        do {
            try await PostProcessor().verifyLocalOllama(baseURL: config.effectiveBaseURL, model: config.model)
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func pollOllamaLoop() async {
        while !Task.isCancelled {
            await refreshOnce()
            try? await Task.sleep(nanoseconds: 12_000_000_000)
        }
    }
}
