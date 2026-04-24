import SwiftUI

public struct ProviderPickerView: View {
    @Binding public var selectedId: String

    public init(selectedId: Binding<String>) {
        _selectedId = selectedId
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
            ForEach(ProviderRegistry.presets) { p in
                providerButton(p)
            }
        }
    }

    private func providerButton(_ p: ProviderPreset) -> some View {
        let isSelected = (p.id == selectedId)
        return Button {
            selectedId = p.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(p.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    privacyPill(p.privacy)
                }
                Text(p.defaultModel.isEmpty ? "User-supplied base URL" : p.defaultModel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(p.rateLimitNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func privacyPill(_ p: PrivacyPolicy) -> some View {
        Text(p.label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(p.color.opacity(0.18)))
            .foregroundStyle(p.color)
    }
}
