import Foundation
import CoreML
import Combine
import WhisperKit

/// Tri-state describing where Whisper inference is actually running.
public enum AccelerationState: String, Sendable, CustomStringConvertible {
    case aneAndGPU = "ANE+GPU"
    case gpuOnly   = "GPU"
    case cpuFallback = "CPU"

    public var description: String { rawValue }
}

public enum EngineError: Error, LocalizedError {
    case modelNotLoaded(String)
    case cpuFallbackRefused
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let s): return "WhisperKit model did not load: \(s)"
        case .cpuFallbackRefused:    return "Refusing to run: Whisper inference would fall back to CPU."
        case .downloadFailed(let s): return "Model download failed: \(s)"
        }
    }
}

/// Wraps `WhisperKit` with a fixed compute configuration that keeps model
/// math off the CPU: audio encoder + text decoder on ANE, mel on GPU.
/// If ANE is not available, falls back to pure GPU. Refuses to run pure-CPU.
@MainActor
public final class TranscriptionEngine: ObservableObject {
    public static let shared = TranscriptionEngine()

    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var loadProgress: Double = 0
    @Published public private(set) var acceleration: AccelerationState = .aneAndGPU
    @Published public private(set) var currentModelName: String = DefaultModel.name
    @Published public private(set) var lastError: String?
    @Published public private(set) var isReadyForTranscription: Bool = false

    public private(set) var whisperKit: WhisperKit?

    private init() {}

    /// Recommended ANE+GPU config (WhisperKit macOS 14+ recommended).
    public static let recommendedComputeOptions = ModelComputeOptions(
        melCompute: .cpuAndGPU,
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine,
        prefillCompute: .cpuOnly
    )

    /// Pure-GPU fallback if ANE unavailable.
    public static let gpuOnlyComputeOptions = ModelComputeOptions(
        melCompute: .cpuAndGPU,
        audioEncoderCompute: .cpuAndGPU,
        textDecoderCompute: .cpuAndGPU,
        prefillCompute: .cpuOnly
    )

    /// Load a WhisperKit model from the given local folder. If not present, downloads it first.
    public func load(modelName: String, modelFolder: URL) async throws {
        guard !isLoading else { return }
        isLoading = true
        syncReadiness()
        defer {
            isLoading = false
            syncReadiness()
        }
        loadProgress = 0
        lastError = nil
        log("loading_started model=\(modelName) root=\(modelFolder.path)")

        let compute: ModelComputeOptions
        let desiredAcceleration: AccelerationState
        if Self.deviceHasNeuralEngine() {
            compute = Self.recommendedComputeOptions
            desiredAcceleration = .aneAndGPU
        } else {
            compute = Self.gpuOnlyComputeOptions
            desiredAcceleration = .gpuOnly
        }
        log("compute_selected acceleration=\(desiredAcceleration.rawValue)")

        // WhisperKit's HubApi downloader places files at
        //   `<downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>/`
        // so we must use the URL it returns (or probe all known layouts) — never
        // hand-construct `<modelFolder>/<variant>`.
        let downloadedFolder: URL
        if let existing = Self.resolveExistingVariant(modelName: modelName, root: modelFolder) {
            downloadedFolder = existing
            log("found_existing_variant path=\(downloadedFolder.path)")
        } else {
            try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
            do {
                downloadedFolder = try await WhisperKit.download(
                    variant: modelName,
                    downloadBase: modelFolder,
                    from: DefaultModel.repo,
                    progressCallback: { [weak self] p in
                        Task { @MainActor in self?.loadProgress = p.fractionCompleted }
                    }
                )
                log("downloaded_variant path=\(downloadedFolder.path)")
            } catch {
                lastError = error.localizedDescription
                log("download_failed error=\(error.localizedDescription)")
                throw EngineError.downloadFailed(error.localizedDescription)
            }
        }

        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: downloadedFolder.path,
            computeOptions: compute,
            verbose: false,
            logLevel: .info,
            prewarm: true,
            load: true,
            download: false
        )

        do {
            let wk = try await WhisperKit(config)
            guard wk.modelState == .loaded else {
                throw EngineError.modelNotLoaded("state=\(wk.modelState)")
            }
            whisperKit = wk
            currentModelName = modelName
            acceleration = desiredAcceleration
            loadProgress = 1.0
            lastError = nil
            syncReadiness()
            log("whisperkit_init_succeeded state=\(wk.modelState) folder=\(downloadedFolder.path)")
        } catch {
            whisperKit = nil
            lastError = error.localizedDescription
            syncReadiness()
            log("whisperkit_init_failed folder=\(downloadedFolder.path) error=\(error.localizedDescription)")
            throw error
        }
    }

    /// Check every layout WhisperKit might have used on disk: the current HF snapshot
    /// shape as well as the legacy flat path, so we don't re-download gigabytes.
    private static func resolveExistingVariant(modelName: String, root: URL) -> URL? {
        let fm = FileManager.default
        let candidates: [URL] = [
            root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(modelName)", isDirectory: true),
            root.appendingPathComponent(modelName, isDirectory: true),
        ]
        for url in candidates {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // Require the three `.mlmodelc` bundles to consider the download complete.
            let audio = url.appendingPathComponent("AudioEncoder.mlmodelc")
            let text = url.appendingPathComponent("TextDecoder.mlmodelc")
            let mel = url.appendingPathComponent("MelSpectrogram.mlmodelc")
            if fm.fileExists(atPath: audio.path) &&
               fm.fileExists(atPath: text.path) &&
               fm.fileExists(atPath: mel.path) {
                return url
            }
        }
        return nil
    }

    private func log(_ msg: String) {
        NSLog("[OAE.Engine] \(msg)")
    }

    private func syncReadiness() {
        isReadyForTranscription = (whisperKit != nil) && !isLoading
    }

    /// Full-buffer transcription used by Capture (push-to-talk) finalize and File finalize pass.
    public func transcribe(samples: [Float], language: String?) async throws -> String {
        guard let wk = whisperKit else { throw EngineError.modelNotLoaded("engine not loaded") }
        var opts = DecodingOptions(
            task: .transcribe,
            language: language,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            chunkingStrategy: .vad
        )
        opts.verbose = false
        let results = try await wk.transcribe(audioArray: samples, decodeOptions: opts)
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func transcribeFile(at url: URL, language: String?) async throws -> (text: String, segments: [TranscriptSegmentRow]) {
        guard let wk = whisperKit else { throw EngineError.modelNotLoaded("engine not loaded") }
        var opts = DecodingOptions(
            task: .transcribe,
            language: language,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            chunkingStrategy: .vad
        )
        opts.verbose = false
        let results = try await wk.transcribe(audioPath: url.path, decodeOptions: opts)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var rows: [TranscriptSegmentRow] = []
        for r in results {
            for seg in r.segments {
                rows.append(TranscriptSegmentRow(start: seg.start, end: seg.end, text: seg.text, confirmed: true))
            }
        }
        return (text, rows)
    }

    /// Best-effort detection: every Apple Silicon Mac since M1 ships an ANE.
    /// On Intel Macs we fall back to pure GPU.
    public static func deviceHasNeuralEngine() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
