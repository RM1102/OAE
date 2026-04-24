import Foundation

/// OpenAI-compatible Chat Completions client. Every supported provider
/// exposes this shape; only the base URL and the API key change.
public struct PostProcessor: Sendable {
    public struct Request: Sendable {
        public var transcript: String
        public var prompt: PromptTemplate
        public var provider: ProviderUserConfig
        public var apiKey: String
        public init(transcript: String, prompt: PromptTemplate, provider: ProviderUserConfig, apiKey: String) {
            self.transcript = transcript; self.prompt = prompt
            self.provider = provider; self.apiKey = apiKey
        }
    }

    public enum StreamEvent: Sendable {
        case token(String)     // delta content
        case done(String)      // full text accumulated
        case rateLimitInfo(remainingRequests: Int?, resetSeconds: Int?)
    }

    public enum ClientError: Error, LocalizedError {
        case emptyKey
        case emptyBaseURL
        case httpStatus(Int, String)
        case invalidResponse
        public var errorDescription: String? {
            switch self {
            case .emptyKey: return "Add an API key to your selected provider before running post-processing."
            case .emptyBaseURL: return "This provider has no base URL. Set one in Settings → Post Process → Custom."
            case .httpStatus(let code, let body):
                return "Provider returned HTTP \(code)\n\(body)"
            case .invalidResponse: return "Unexpected response shape from provider."
            }
        }
    }

    public enum LocalReadinessError: Error, LocalizedError {
        case ollamaMissing
        case daemonUnreachable(String)
        case modelMissing(String)

        public var errorDescription: String? {
            switch self {
            case .ollamaMissing:
                return "Ollama is not installed. Install with `brew install ollama` then run `ollama serve`."
            case .daemonUnreachable(let base):
                return "Ollama server not reachable at \(base). Run `ollama serve` and retry."
            case .modelMissing(let model):
                return "Model \(model) is not pulled locally. Run `ollama pull \(model)` then retry."
            }
        }
    }

    public init() {}

    public func verifyLocalOllama(baseURL: String, model: String) async throws {
        if !Self.isOllamaCLIInstalled() {
            throw LocalReadinessError.ollamaMissing
        }
        // Preset uses OpenAI-compatible root …/v1; Ollama's native `/api/tags` lives on the host root (no `/v1`).
        let nativeRoot = Self.ollamaNativeAPIRoot(fromOpenAICompatibleBase: baseURL)
        let tagsPath = "\(nativeRoot)/api/tags"
        guard let tagsURL = URL(string: tagsPath) else {
            throw LocalReadinessError.daemonUnreachable(baseURL)
        }
        var req = URLRequest(url: tagsURL)
        req.timeoutInterval = 6
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalReadinessError.daemonUnreachable(nativeRoot)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LocalReadinessError.daemonUnreachable(nativeRoot)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            throw LocalReadinessError.daemonUnreachable(nativeRoot)
        }
        let names = models.compactMap { $0["name"] as? String }
        let hasModel = names.contains(where: { $0 == model || $0.hasSuffix("/\(model)") })
        guard hasModel else {
            throw LocalReadinessError.modelMissing(model)
        }
    }

    /// Strips a trailing `/v1` OpenAI shim so native endpoints like `/api/tags` resolve correctly.
    public static func ollamaNativeAPIRoot(fromOpenAICompatibleBase: String) -> String {
        var s = fromOpenAICompatibleBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/v1") {
            s = String(s.dropLast(3))
            while s.hasSuffix("/") { s.removeLast() }
        }
        return s
    }

    /// Whether the `ollama` CLI is on `PATH` (install from https://ollama.com).
    public static func isOllamaCLIInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "-lc", "command -v ollama >/dev/null 2>&1"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// If the Ollama HTTP API is down, opens **Ollama.app** (when present) and waits until `/api/tags` responds.
    public func ensureOllamaDaemonReachable(openAICompatibleBaseURL: String) async throws {
        if !Self.isOllamaCLIInstalled() {
            throw LocalReadinessError.ollamaMissing
        }
        let native = Self.ollamaNativeAPIRoot(fromOpenAICompatibleBase: openAICompatibleBaseURL)
        if await OllamaBootstrap.ping(nativeRoot: native) { return }

        let opened = await MainActor.run { OllamaBootstrap.openOllamaApp() }
        if !opened {
            throw LocalReadinessError.daemonUnreachable(
                "Install the Ollama app from https://ollama.com (the menu bar app), then try again."
            )
        }
        if await OllamaBootstrap.waitForDaemon(nativeRoot: native, timeoutSeconds: 45) { return }
        throw LocalReadinessError.daemonUnreachable(
            "Ollama didn’t respond in time. Open the Ollama app from your Applications folder, wait a few seconds, then tap Refresh status."
        )
    }

    public func stream(_ request: Request) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    try await self.runStreaming(request: request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStreaming(request: Request,
                              continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        let isLocalProvider = request.provider.presetId == "local-ollama"
        if !isLocalProvider {
            guard !request.apiKey.isEmpty else { throw ClientError.emptyKey }
        }
        let base = request.provider.effectiveBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let url = URL(string: base.hasSuffix("/chat/completions")
                                                   ? base
                                                   : base.trimmingCharacters(in: .init(charactersIn: "/")) + "/chat/completions")
        else { throw ClientError.emptyBaseURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !request.apiKey.isEmpty {
            req.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let userContent = request.prompt.user.replacingOccurrences(of: "{{transcript}}", with: request.transcript)
        let body: [String: Any] = [
            "model": request.provider.model,
            "temperature": request.prompt.temperature,
            "stream": true,
            "messages": [
                ["role": "system", "content": request.prompt.system],
                ["role": "user",   "content": userContent]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        if let rem = http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests").flatMap({ Int($0) }) {
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset-requests").flatMap({ Int($0) })
            continuation.yield(.rateLimitInfo(remainingRequests: rem, resetSeconds: reset))
        }

        guard (200..<300).contains(http.statusCode) else {
            var err = ""
            for try await line in bytes.lines { err += line + "\n"; if err.count > 2048 { break } }
            throw ClientError.httpStatus(http.statusCode, err)
        }

        var full = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any] else { continue }
            if let content = delta["content"] as? String, !content.isEmpty {
                full += content
                continuation.yield(.token(content))
            }
        }

        continuation.yield(.done(full))
    }

    /// Non-streaming convenience for cases where streaming fails or is not needed.
    public func runOnce(_ request: Request) async throws -> String {
        var out = ""
        for try await ev in stream(request) {
            if case let .token(t) = ev { out += t }
            if case let .done(f)  = ev { return f.isEmpty ? out : f }
        }
        return out
    }
}
