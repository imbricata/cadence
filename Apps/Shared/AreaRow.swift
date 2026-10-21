import SwiftUI
import CadenceCore

struct AreaRow: View {
    let area: Area
    /// nil with `showsForm` = "Calibrating".
    var formPercent: Double? = nil
    var showsForm = true

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: area.symbolName)
                .frame(width: 26)
                .foregroundStyle(area.color.base)
            Text(area.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsForm {
                if let p = formPercent {
                    Text("\(Int(p.rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("Calibrating").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct BlockSheetTarget: Identifiable {
    let id: String
    let event: CalendarEvent
    let area: Area
}
