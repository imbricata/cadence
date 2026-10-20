import SwiftUI
import CadenceCore

public let symbolChoices: [String] = [
    "circle", "heart", "book", "dumbbell", "graduationcap",
    "briefcase", "paintbrush", "laptopcomputer", "music.note",
    "fork.knife", "house", "leaf", "figure.walk", "pencil",
    "gift", "waveform", "camera", "gamecontroller", "stethoscope", "airplane"
]

struct AreaRow: View {
    let area: Area
    var formPercent: Double? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: area.symbolName)
                .frame(width: 26)
                .foregroundStyle(area.color.base)
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