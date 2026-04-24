import SwiftUI

public struct WaveformView: View {
    public var levels: [Float]
    public var active: Bool
    public init(levels: [Float], active: Bool) {
        self.levels = levels; self.active = active
    }

    public var body: some View {
        GeometryReader { geo in
            let barCount = levels.count
            let spacing: CGFloat = 3
            let available = geo.size.width - CGFloat(barCount - 1) * spacing
            let barWidth = max(2, available / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let l = max(0.02, CGFloat(levels[i]) * 3.2)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(active ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.5))
                        .frame(width: barWidth, height: max(2, geo.size.height * min(1, l)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: levels)
        }
    }
}
