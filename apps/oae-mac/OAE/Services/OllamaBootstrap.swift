import AppKit
import Foundation

/// Brings the local Ollama daemon up for non-technical users (open app + poll `/api/tags`).
enum OllamaBootstrap {
    /// `GET {nativeRoot}/api/tags` — same contract as `PostProcessor.verifyLocalOllama` (native root, no `/v1`).
    static func ping(nativeRoot: String) async -> Bool {
        let root = nativeRoot.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    @MainActor
    static func openOllamaApp() -> Bool {
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Ollama.app", isDirectory: true)
        let candidates = [
            URL(fileURLWithPath: "/Applications/Ollama.app", isDirectory: true),
            homeApps
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }

    /// Polls until `ping` succeeds or `timeoutSeconds` elapses.
    static func waitForDaemon(nativeRoot: String, timeoutSeconds: TimeInterval = 45) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if await ping(nativeRoot: nativeRoot) { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }
}
