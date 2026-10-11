import SwiftUI
import CadenceCore

public let symbolChoices: [String] = [
    "circle", "heart", "book", "dumbbell", "graduationcap",
    "briefcase", "paintbrush", "laptopcomputer", "music.note",
    "fork.knife", "house", "leaf", "figure.walk", "pencil",
    "gift", "waveform", "camera", "gamecontroller", "stethoscope", "airplane"
]

struct AreaColorDot: View {
    let colorHex: String
    var size: CGFloat = 10
    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
    }
}

struct AreaRow: View {
    let area: Area
    var formPercent: Double? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: area.symbolName)
                .frame(width: 26)
                .foregroundStyle(Color(hex: area.colorHex))
            Text(area.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            FormLabel(percent: formPercent)
        }
    }
}

struct BlockSheetTarget: Identifiable {
    let id: String
    let event: CalendarEvent
    let area: Area
}