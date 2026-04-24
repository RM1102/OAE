import Foundation
import Combine
import WhisperKit

public struct AvailableModel: Identifiable, Hashable, Sendable {
    public let id: String      // variant name
    public let displayName: String
    public let sizeLabel: String
    public let notes: String
    public var installed: Bool = false

    public init(id: String, displayName: String, sizeLabel: String, notes: String, installed: Bool = false) {
        self.id = id; self.displayName = displayName; self.sizeLabel = sizeLabel
        self.notes = notes; self.installed = installed
    }
}

/// Manages WhisperKit CoreML models stored under
/// `~/Library/Application Support/OAE/Models/` and lets the UI download
/// them on demand.
@MainActor
public final class ModelStore: ObservableObject {
    public static let shared = ModelStore()

    @Published public private(set) var models: [AvailableModel] = []
    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var activeDownload: String?

    public let rootURL: URL

    private init() {
        let appSupport = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
        let root = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("OAE", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        self.rootURL = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        refresh()
    }

    public static let catalog: [AvailableModel] = [
        .init(id: "openai_whisper-large-v3-v20240930_626MB",
              displayName: "Whisper Large v3 (626 MB, default)",
              sizeLabel: "626 MB",
              notes: "Balanced accuracy. Recommended default for macOS 14+."),
        .init(id: "openai_whisper-large-v3-turbo_632MB",
              displayName: "Whisper Large v3 Turbo (632 MB)",
              sizeLabel: "632 MB",
              notes: "Near-realtime. Slightly less accurate than Large v3."),
        .init(id: "distil-whisper_distil-large-v3",
              displayName: "Distil-Whisper Large v3",
              sizeLabel: "~1.1 GB",
              notes: "Distilled model. Very fast."),
        .init(id: "openai_whisper-small",
              displayName: "Whisper Small",
              sizeLabel: "~244 MB",
              notes: "Low-RAM option. Lower accuracy."),
        .init(id: "openai_whisper-base",
              displayName: "Whisper Base",
              sizeLabel: "~74 MB",
              notes: "Tiny footprint. Lowest accuracy of the set.")
    ]

    public func refresh() {
        let installed = Set(installedModelNames())
        models = Self.catalog.map { m in
            var c = m
            c.installed = installed.contains(m.id)
            return c
        }
    }

    public func installedModelNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
    }

    public func folder(for model: String) -> URL {
        rootURL.appendingPathComponent(model, isDirectory: true)
    }

    public func isInstalled(_ model: String) -> Bool {
        let fm = FileManager.default
        // Flat layout written by `installBundledModelsIfAvailable`.
        if fm.fileExists(atPath: folder(for: model).path) { return true }
        // HuggingFace Hub layout produced by `WhisperKit.download(...)`.
        let nested = rootURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(model, isDirectory: true)
        return fm.fileExists(atPath: nested.path)
    }

    public func download(_ model: String) async throws {
        guard !isDownloading else { return }
        isDownloading = true
        activeDownload = model
        downloadProgress = 0
        defer {
            isDownloading = false
            activeDownload = nil
            refresh()
        }
        _ = try await WhisperKit.download(
            variant: model,
            downloadBase: rootURL,
            from: DefaultModel.repo,
            progressCallback: { [weak self] p in
                Task { @MainActor in self?.downloadProgress = p.fractionCompleted }
            }
        )
    }

    public func delete(_ model: String) throws {
        let url = folder(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        refresh()
    }

    public func diskUsageBytes() -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let v = try? url.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(v?.fileSize ?? 0)
            }
        }
        return total
    }

    public func installBundledModelsIfAvailable(requiredModel: String) throws {
        if isInstalled(requiredModel) {
            refresh()
            return
        }
        guard let sourceRoot = bundledModelsSourceURL() else {
            throw NSError(domain: "OAE.ModelStore", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Bundled models not found. Ask for the shipping kit with model files."
            ])
        }
        let fm = FileManager.default
        guard let sourceModel = locateBundledModelFolder(requiredModel: requiredModel, root: sourceRoot) else {
            throw NSError(domain: "OAE.ModelStore", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Bundled model \(requiredModel) not found in shipping kit."
            ])
        }
        let destination = folder(for: requiredModel)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.copyItem(at: sourceModel, to: destination)

        // Lightweight verification: folder copied and contains at least one file.
        let contents = try fm.contentsOfDirectory(atPath: destination.path)
        guard !contents.isEmpty else {
            throw NSError(domain: "OAE.ModelStore", code: 422, userInfo: [
                NSLocalizedDescriptionKey: "Copied model folder is empty. Re-run install.command."
            ])
        }
        refresh()
    }

    private func bundledModelsSourceURL() -> URL? {
        let fm = FileManager.default
        if let resource = Bundle.main.resourceURL?
            .appendingPathComponent("BundledModels", isDirectory: true),
           fm.fileExists(atPath: resource.path) {
            return resource
        }
        let appSupport = rootURL.deletingLastPathComponent()
        let staged = appSupport.appendingPathComponent("BundledModels", isDirectory: true)
        if fm.fileExists(atPath: staged.path) {
            return staged
        }
        return nil
    }

    private func locateBundledModelFolder(requiredModel: String, root: URL) -> URL? {
        let fm = FileManager.default
        let direct = root.appendingPathComponent(requiredModel, isDirectory: true)
        if fm.fileExists(atPath: direct.path) { return direct }

        // Support nested layouts like BundledModels/<repo>/<variant>.
        guard let levelOne = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        for first in levelOne {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let candidate = first.appendingPathComponent(requiredModel, isDirectory: true)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
