import Foundation
import Combine

public struct PromptTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var system: String
    public var user: String
    public var temperature: Double
    public var isBuiltin: Bool

    public init(id: UUID = UUID(), name: String, system: String, user: String,
                temperature: Double = 0.2, isBuiltin: Bool = false) {
        self.id = id; self.name = name; self.system = system; self.user = user
        self.temperature = temperature; self.isBuiltin = isBuiltin
    }
}

/// Loads/saves prompt templates at
/// `~/Library/Application Support/OAE/prompts.json`. Ships with a built-in
/// set that cannot be deleted but can be duplicated and edited.
@MainActor
public final class PromptLibrary: ObservableObject {
    public static let shared = PromptLibrary()

    @Published public private(set) var prompts: [PromptTemplate] = []

    private let storeURL: URL

    private init() {
        let appSupport = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
        let root = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("OAE", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.storeURL = root.appendingPathComponent("prompts.json")
        reload()
    }

    public func reload() {
        let builtin = Self.builtinTemplates
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([PromptTemplate].self, from: data) {
            var merged = builtin
            for p in decoded where !builtin.contains(where: { $0.id == p.id }) {
                merged.append(p)
            }
            prompts = merged
        } else {
            prompts = builtin
        }
    }

    public func save() {
        let userOnly = prompts.filter { !$0.isBuiltin }
        if let data = try? JSONEncoder().encode(userOnly) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    public func add(_ p: PromptTemplate) {
        var np = p; np.isBuiltin = false
        prompts.append(np); save()
    }
    public func update(_ p: PromptTemplate) {
        guard let i = prompts.firstIndex(where: { $0.id == p.id }) else { return }
        var np = p
        np.isBuiltin = prompts[i].isBuiltin
        prompts[i] = np
        save()
    }
    public func duplicate(_ p: PromptTemplate) {
        var c = p; c.id = UUID(); c.name = "\(p.name) (copy)"; c.isBuiltin = false
        prompts.append(c); save()
    }
    public func remove(_ id: UUID) {
        prompts.removeAll { $0.id == id && !$0.isBuiltin }
        save()
    }

    public static let builtinTemplates: [PromptTemplate] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA01")!,
              name: "Clean up",
              system: "You are a careful editor. Keep the speaker's words and meaning. Remove filler words (um, uh, like, you know). Fix obvious mis-hearings only if context makes them unambiguous. Do not paraphrase, do not summarize, do not add content. Preserve original language.",
              user: "Clean up this transcript. Return only the cleaned text.\n\nTranscript:\n{{transcript}}",
              temperature: 0.1, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA02")!,
              name: "Fix grammar and punctuation",
              system: "You apply minimal grammar and punctuation fixes only. Never paraphrase, reorder, or add content. Preserve original language and tone.",
              user: "Fix grammar and punctuation. Return only the corrected text.\n\nTranscript:\n{{transcript}}",
              temperature: 0.1, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA03")!,
              name: "Summarize (bullets)",
              system: "You produce faithful, concise bullet summaries. No speculation.",
              user: "Summarize the following transcript as 3 to 7 short bullet points.\n\nTranscript:\n{{transcript}}",
              temperature: 0.2, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA04")!,
              name: "Executive summary",
              system: "You produce one-paragraph executive summaries. Factual, non-speculative, no new information.",
              user: "Write a single concise paragraph summarising the transcript.\n\nTranscript:\n{{transcript}}",
              temperature: 0.2, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA05")!,
              name: "Translate to English",
              system: "You translate literally. Preserve tone and proper nouns. Do not add commentary.",
              user: "Translate the following transcript to English. Return only the translation.\n\nTranscript:\n{{transcript}}",
              temperature: 0.1, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA06")!,
              name: "Format as email",
              system: "You format speech into a professional email. Preserve meaning. Add a subject line, greeting, body, and signoff. Do not invent facts.",
              user: "Format the following into a short, clear email.\n\nTranscript:\n{{transcript}}",
              temperature: 0.3, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA07")!,
              name: "Meeting notes",
              system: "You turn spoken notes into structured meeting notes with sections: Agenda, Decisions, Action items (with owners if mentioned). Do not add content.",
              user: "Produce meeting notes from this transcript.\n\nTranscript:\n{{transcript}}",
              temperature: 0.2, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA08")!,
              name: "Math Unicode + LaTeX",
              system: "You normalize spoken math and equations. Return STRICT JSON with keys unicode and latex only. unicode should use real symbols (∂, ∇, μ, ², etc.). latex should be valid LaTeX expression text. Do not include markdown fences.",
              user: "Convert this transcript to equation form and return JSON only with {\"unicode\":\"...\",\"latex\":\"...\"}.\n\nTranscript:\n{{transcript}}",
              temperature: 0.0, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA09")!,
              name: "Math Unicode only",
              system: "Convert spoken mathematical statements into concise Unicode math text. Use symbols like ∂, ∑, μ, α, β, ∇, and superscripts where appropriate.",
              user: "Rewrite this transcript as clean Unicode math text. Return only the rewritten text.\n\nTranscript:\n{{transcript}}",
              temperature: 0.0, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA0C")!,
              name: "Live dictate — Unicode tail",
              system: """
You receive a SHORT, recent excerpt of a live scientific lecture (automatic transcription; may end mid-sentence).
- Convert only obvious spoken-math fragments to Unicode (∂ ∇ × · ÷ ∑ ∫ √ Greek letters, simple sub/superscripts like x² or aₙ when trivial).
- Keep all non-math words, order, and hedges unchanged. Do not summarize, do not add sentences, do not invent equations.
- Return only the rewritten excerpt as plain text (no JSON, no marker lines, no headings).
""",
              user: "Excerpt:\n{{transcript}}",
              temperature: 0.05, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA0D")!,
              name: "Live dictate — study batch",
              system: """
You receive a LONGER excerpt of an ongoing scientific lecture (ASR text only). The student still has the board.
- Do NOT paste back the full transcript.
- First line must be exactly: (Live study batch — inferred; verify on the board)
- Then 3–14 bullet lines. Each substantive bullet must start with “• (inferred) ” or “• (from context) ”.
- Use Unicode for equations where strongly justified by the excerpt. Connect fragments only when the same reading is very likely.
- If nothing is safe to add: output only the first line, then a second line: (No safe batch notes for this window.)
- Plain text only. No JSON, no <<<OAE_STUDY_SUPPLEMENT>>> marker.
""",
              user: "Lecture excerpt:\n{{transcript}}",
              temperature: 0.12, isBuiltin: true),

        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000AA0B")!,
              name: "Scientific lecture → Unicode + study supplement",
              system: """
You are editing a live lecture transcript for a student who will also look at the board/slides. The transcript is from automatic speech recognition: math is often spelled as words (“partial p partial t”, “del squared phi”, “dee w d t”, “nabla dot E”, “sigma”, “mu nought”, “integral from zero to infinity”, “x squared plus y squared”).

PRIMARY CONTRACT — VERBATIM LECTURE (PART A), LIGHT NOTATION TOUCH
- Preserve the professor’s spoken flow: same language, same order of ideas, same hedges (“sort of”, “roughly”, “you can think of it as”), repetitions, and oral signposting (“so”, “now”, “look at this term”). Do not summarize, condense, lecture back, moralize, or add facts the speaker did not say.
- Change only what is clearly mathematical notation encoded as words/letters. Everything that is plain explanation, history, analogy, or pedagogy stays as words unless it is explicitly a symbol name being spelled out for the board.
- When in doubt, leave the ASR wording. A slightly ugly transcript beats a wrong equation.

SECONDARY GOAL — UNICODE MATH IN PLACE (STILL PART A ONLY)
- Where intent is clear, replace spoken/letter math with compact Unicode: ∂ ∇ × · ÷ ± ∓ ≈ ≠ ≤ ≥ → ↔ ∑ ∏ ∫ ∮ √ ∞ ∅ ∈ ∉ ⊂ ∪ ∩ ∧ ∨ ¬ ∀ ∃, superscripts/subscripts (x², aₙ, only when simple and readable), fractions inline (a/b or ½-style when natural), and standard Greek (α β γ δ ε θ λ μ ν π ρ σ τ φ χ ψ ω Γ Δ Θ Λ Ξ Π Σ Φ Ψ Ω).
- Prefer ∂ vs d using context: fields, thermodynamics, PDEs → partial ∂; total derivative along a path → d when clearly meant.
- Distinguish spoken “times” as multiplication vs cross product vs tensor product from context; use · or × or ⊗ sparingly and only when obvious.

BOARD, BRACKETS, AND SILENT DRAWING (PART A ONLY)
- When the discourse makes grouping obvious (“everything in the numerator”, “this whole expression”, “the term in the curly brackets on the board”), you may insert minimal (), [], {} around the smallest relevant fragment.
- If the transcript does not constrain an expression, do NOT invent a long formula in Part A. Leave a verbal anchor or a tiny hint only.

PART B — STUDY SUPPLEMENT (“OWN BRAIN”, HIGHER RISK)
- After Part A, you may add a separate block where you use lecture context to help the student: restate key equations in cleaner standalone Unicode form, fill in brackets/parentheses the speaker drew but did not say aloud, or connect fragments **only when** Part A plus obvious course-level conventions make a single reading very likely.
- Every substantive line in Part B must be honest about uncertainty: start inferred items with “• (inferred) ” or “• (from context) ”. If you cannot justify a line from the transcript, omit it.
- Never contradict Part A. Do not introduce new physical claims, numbers, or boundary conditions the speaker never mentioned.
- If there is nothing safe to add beyond Part A, Part B should be exactly one line: (No additional reconstructions — rely on Part A and the board.)

RISK NOTE (FOR YOUR BEHAVIOR, NOT FOR THE USER)
- Reconstructed equations can be wrong and confuse students who skip the board. That is why Part A stays conservative and Part B is explicitly labeled inference.

SCIENTIFIC BREADTH (APPLY WHEN RELEVANT, NEVER FORCE)
- Classical mechanics, E&M, thermo/stat mech, quantum (words or light Dirac notation), linear algebra, analysis/ODE/PDE, chemistry formulas, geometry — same as before: symbolize only when the spoken form maps cleanly in Part A; in Part B you may assemble fuller lines only when strongly supported.

OUTPUT FORMAT (STRICT — OAE SPLITS ON THIS MARKER)
1) Part A only first: the full upgraded transcript (plain text, no LaTeX, no markdown code fences, no JSON).
2) Then a single line containing exactly this text and nothing else on that line:
<<<OAE_STUDY_SUPPLEMENT>>>
3) Then Part B: the study supplement (plain text). No text after Part B.
""",
              user: """
Produce Part A then the marker line then Part B as specified in the system message.

Part A: verbatim lecture with Unicode math in place (conservative). Part B: optional inferred notes and fuller equations where strongly justified; label inferences; never contradict Part A.

Transcript:
{{transcript}}
""",
              temperature: 0.12, isBuiltin: true)
    ]
}
