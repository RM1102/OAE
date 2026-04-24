import Foundation
import SwiftUI

public enum PrivacyPolicy: String, Codable, Sendable {
    case noTraining
    case mayTrain
    case local

    public var label: String {
        switch self {
        case .noTraining: return "No training"
        case .mayTrain:   return "May train"
        case .local:      return "Local"
        }
    }
    public var color: Color {
        switch self {
        case .noTraining: return .green
        case .mayTrain:   return .orange
        case .local:      return .blue
        }
    }
}

public struct ProviderPreset: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let defaultModel: String
    public let privacy: PrivacyPolicy
    public let signupURL: String
    public let signupNote: String
    public let rateLimitNote: String
    public let isCustom: Bool

    public init(id: String, name: String, baseURL: String, defaultModel: String,
                privacy: PrivacyPolicy, signupURL: String, signupNote: String,
                rateLimitNote: String, isCustom: Bool = false) {
        self.id = id; self.name = name; self.baseURL = baseURL; self.defaultModel = defaultModel
        self.privacy = privacy; self.signupURL = signupURL; self.signupNote = signupNote
        self.rateLimitNote = rateLimitNote; self.isCustom = isCustom
    }
}

public enum ProviderRegistry {
    public static let presets: [ProviderPreset] = [
        .init(id: "local-ollama",
              name: "Local Ollama (recommended)",
              baseURL: "http://127.0.0.1:11434/v1",
              defaultModel: "gemma2:2b",
              privacy: .local,
              signupURL: "https://ollama.com/download",
              signupNote: "Install Ollama and run: ollama pull gemma2:2b",
              rateLimitNote: "No API key needed. Runs fully local on your Mac."),

        .init(id: "groq",
              name: "Groq",
              baseURL: "https://api.groq.com/openai/v1",
              defaultModel: "llama-3.3-70b-versatile",
              privacy: .noTraining,
              signupURL: "https://console.groq.com",
              signupNote: "Sign in with Google → API Keys → Create Key. No credit card.",
              rateLimitNote: "~30 RPM / 30K TPM free. Sub-second latency."),

        .init(id: "cerebras",
              name: "Cerebras",
              baseURL: "https://api.cerebras.ai/v1",
              defaultModel: "llama3.1-8b",
              privacy: .noTraining,
              signupURL: "https://cloud.cerebras.ai",
              signupNote: "Sign in → API Keys → Create. No credit card.",
              rateLimitNote: "~30 RPM free. Fastest inference on the market."),

        .init(id: "github",
              name: "GitHub Models",
              baseURL: "https://models.github.ai/inference",
              defaultModel: "openai/gpt-4o-mini",
              privacy: .noTraining,
              signupURL: "https://github.com/settings/tokens",
              signupNote: "Create a Personal Access Token with the models:read scope.",
              rateLimitNote: "~15 RPM free. Includes GPT-4o-mini, Llama 3.3 70B, Phi-4."),

        .init(id: "nvidia",
              name: "NVIDIA NIM",
              baseURL: "https://integrate.api.nvidia.com/v1",
              defaultModel: "meta/llama-3.3-70b-instruct",
              privacy: .noTraining,
              signupURL: "https://build.nvidia.com",
              signupNote: "Sign in → create API key.",
              rateLimitNote: "~40 RPM free. Includes DeepSeek R1, Llama 3.1 405B."),

        .init(id: "openrouter",
              name: "OpenRouter",
              baseURL: "https://openrouter.ai/api/v1",
              defaultModel: "meta-llama/llama-3.3-70b-instruct:free",
              privacy: .mayTrain,
              signupURL: "https://openrouter.ai",
              signupNote: "Sign up → Keys → Create. Use any model id ending in :free.",
              rateLimitNote: "20 RPM / 50 RPD on :free models."),

        .init(id: "gemini",
              name: "Google Gemini",
              baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
              defaultModel: "gemini-2.5-flash",
              privacy: .mayTrain,
              signupURL: "https://aistudio.google.com",
              signupNote: "AI Studio → Get API key. Free tier may train on prompts.",
              rateLimitNote: "~10 RPM / 250 RPD free. 1M token context."),

        .init(id: "mistral",
              name: "Mistral",
              baseURL: "https://api.mistral.ai/v1",
              defaultModel: "mistral-small-latest",
              privacy: .mayTrain,
              signupURL: "https://console.mistral.ai",
              signupNote: "Sign up (phone verification) → Experiment tier.",
              rateLimitNote: "~1B tokens/month free. Free-tier may train."),

        .init(id: "custom",
              name: "Custom (OpenAI-compatible)",
              baseURL: "",
              defaultModel: "",
              privacy: .local,
              signupURL: "",
              signupNote: "Point at a local Ollama, LM Studio, or any OpenAI-compatible gateway.",
              rateLimitNote: "Depends on your backend.",
              isCustom: true)
    ]

    public static func preset(id: String) -> ProviderPreset? {
        presets.first { $0.id == id }
    }

    public static var defaultProviderId: String { "local-ollama" }
}

/// Per-provider user-configurable settings persisted outside of Keychain (the
/// key itself lives in Keychain).
public struct ProviderUserConfig: Codable, Hashable, Sendable {
    public var presetId: String
    public var model: String
    public var baseURLOverride: String?

    public init(presetId: String, model: String, baseURLOverride: String? = nil) {
        self.presetId = presetId
        self.model = model
        self.baseURLOverride = baseURLOverride
    }

    public var effectiveBaseURL: String {
        if let o = baseURLOverride, !o.isEmpty { return o }
        return ProviderRegistry.preset(id: presetId)?.baseURL ?? ""
    }
}
