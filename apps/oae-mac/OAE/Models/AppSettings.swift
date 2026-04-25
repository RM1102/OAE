import Foundation
import SwiftUI

public enum TranscriptionLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto, en, es, fr, de, it, pt, ru, ja, zh, ko, hi, ar, nl, pl, tr, sv, no, da, fi, el, he, id, th, vi, uk, cs, ro
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .en: return "English"
        case .es: return "Spanish"
        case .fr: return "French"
        case .de: return "German"
        case .it: return "Italian"
        case .pt: return "Portuguese"
        case .ru: return "Russian"
        case .ja: return "Japanese"
        case .zh: return "Chinese"
        case .ko: return "Korean"
        case .hi: return "Hindi"
        case .ar: return "Arabic"
        case .nl: return "Dutch"
        case .pl: return "Polish"
        case .tr: return "Turkish"
        case .sv: return "Swedish"
        case .no: return "Norwegian"
        case .da: return "Danish"
        case .fi: return "Finnish"
        case .el: return "Greek"
        case .he: return "Hebrew"
        case .id: return "Indonesian"
        case .th: return "Thai"
        case .vi: return "Vietnamese"
        case .uk: return "Ukrainian"
        case .cs: return "Czech"
        case .ro: return "Romanian"
        }
    }
    public var whisperCode: String? { self == .auto ? nil : rawValue }
}

public enum SettingsKey {
    public static let modelName = "oae.modelName"
    public static let language = "oae.language"
    public static let autoCopy = "oae.autoCopy"
    public static let autoPaste = "oae.autoPaste"
    public static let launchAtLogin = "oae.launchAtLogin"
    public static let confirmationSegments = "oae.confirmationSegments"
    public static let lowLatencyLive = "oae.live.lowLatency"
    public static let silenceThreshold = "oae.silenceThreshold"
    public static let selectedProvider = "oae.selectedProvider"
    public static let selectedPrompt = "oae.selectedPrompt"
    public static let selectedLocalModel = "oae.local.model"
    public static let rightOptKeyCode = "oae.ptt.rightKeyCode"
    public static let leftOptKeyCode = "oae.ptt.leftKeyCode"
    public static let onboardedPostProcess = "oae.onboarded.postProcess"
    /// Optional free-form text appended to the post-process system prompt (per run).
    public static let postProcessExtraInstructions = "oae.postprocess.extraInstructions"
    /// Background Unicode + study batches while Dictate is running (local Ollama).
    public static let dictateLivePostProcess = "oae.dictate.livePostProcess"
    /// New words since last live Unicode pass before firing (after debounce).
    public static let dictateLivePostProcessWordStep = "oae.dictate.livePostProcess.wordStep"
    /// New words since last live study batch before firing.
    public static let dictateLivePostProcessStudyStep = "oae.dictate.livePostProcess.studyStep"
    /// Dictate live streaming profile: "ultraLowLatency" or "balanced".
    public static let liveStreamingPreset = "oae.live.streamingPreset"
    /// Number of trailing words allowed to be rewritten during live stabilization.
    public static let dictateRewriteLookbackWords = "oae.dictate.rewriteLookbackWords"
    /// Enables professor shipping setup assistant gating flow.
    public static let shippingRequireSetup = "oae.shipping.requireSetup"
    /// Setup assistant completion flag.
    public static let shippingSetupCompleted = "oae.shipping.setupCompleted"
    /// Tracks whether bundled models were installed from shipping kit.
    public static let shippingModelsReady = "oae.shipping.modelsReady"
    /// Tracks whether Ollama daemon/model setup was completed for shipping kit.
    public static let shippingOllamaReady = "oae.shipping.ollamaReady"
    /// Live subtitle overlay layout: `floating` (draggable island) or `notchStrip` (top-center strip).
    public static let subtitlePresentation = "oae.subtitle.presentation"
    /// Live subtitle caption style.
    public static let subtitleCaptionStyle = "oae.subtitle.captionStyle"
    /// Toggle monospaced subtitle metrics for maximum visual stability.
    public static let subtitleIslandMonospace = "oae.subtitle.islandMonospace"
}

/// Where live subtitles are drawn on screen.
public enum SubtitlePresentationMode: String, CaseIterable, Sendable, Identifiable {
    case floating
    case notchStrip
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .floating: return "Floating island"
        case .notchStrip: return "Top notch strip"
        }
    }
}

public enum SubtitleCaptionStyle: String, CaseIterable, Sendable, Identifiable {
    case classicStable
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .classicStable: return "Classic stable (2-line)"
        }
    }
}

public enum DefaultModel {
    public static let name = "openai_whisper-large-v3-v20240930_626MB"
    public static let repo = "argmaxinc/whisperkit-coreml"
}
