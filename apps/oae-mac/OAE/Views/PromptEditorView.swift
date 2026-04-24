import SwiftUI

public struct PromptEditorView: View {
    @EnvironmentObject var library: PromptLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PromptTemplate
    private let isNew: Bool

    public init(template: PromptTemplate? = nil) {
        if let t = template {
            _draft = State(initialValue: t)
            isNew = false
        } else {
            _draft = State(initialValue: PromptTemplate(
                name: "New Prompt",
                system: "You are a careful editor.",
                user: "Do X to the transcript.\n\nTranscript:\n{{transcript}}",
                temperature: 0.2,
                isBuiltin: false))
            isNew = true
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Create Prompt" : "Edit Prompt")
                .font(.title2.bold())

            LabeledInput(label: "Name") {
                TextField("", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(draft.isBuiltin)
            }

            LabeledInput(label: "System") {
                TextEditor(text: $draft.system)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                    .disabled(draft.isBuiltin)
            }

            LabeledInput(label: "User (supports {{transcript}})") {
                TextEditor(text: $draft.user)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                    .disabled(draft.isBuiltin)
            }

            LabeledInput(label: "Temperature \(String(format: "%.2f", draft.temperature))") {
                Slider(value: $draft.temperature, in: 0...1)
                    .disabled(draft.isBuiltin)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Add" : "Save") {
                    if isNew { library.add(draft) } else { library.update(draft) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.isBuiltin || draft.name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct LabeledInput<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
