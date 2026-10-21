import SwiftUI
import CadenceCore

/// Thin bar for Form: the tick marks 100% (your normal or your target); the bar runs to 200%.
struct FormBar: View {
    let percent: Double?
    var colorHex: String?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                if let percent {
                    Capsule()
                        .fill(colorHex.map { AreaColor($0).base } ?? Color.accentColor)
                        .frame(width: max(4, min(1, percent / 200) * geo.size.width))
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1.5, height: 10)
                    .offset(x: geo.size.width / 2 - 0.75)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct FormLabel: View {
    let percent: Double?
    var body: some View {
        if let percent {
            Text("\(Int(percent.rounded()))%")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(percent >= 100 ? Color.primary : Color.secondary)
        } else {
            Text("Calibrating").font(.caption).foregroundStyle(.secondary)
        }
    }
}
