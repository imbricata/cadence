import SwiftUI
import CadenceCore

/// Filterable Area list shown after dragging out a new block. Type to filter, arrows to move, Return to pick.
struct AreaPickerPopover: View {
    let areas: [Area]
    var onPick: (Area) -> Void

    @State private var query = ""
    @State private var highlight = 0
    @FocusState private var focused: Bool

    private var filtered: [Area] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? areas : areas.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Choose an area", text: $query)
                .textFieldStyle(.plain)
                .padding(Theme.Space.m)
                .focused($focused)
                .onSubmit { pickHighlighted() }
                .onKeyPress(.downArrow) { highlight = min(highlight + 1, max(0, filtered.count - 1)); return .handled }
                .onKeyPress(.upArrow) { highlight = max(0, highlight - 1); return .handled }
            Divider()
            if filtered.isEmpty {
                Text("No matching area").font(.callout).foregroundStyle(.secondary).padding(Theme.Space.m)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, area in
                        Button { onPick(area) } label: {
                            HStack(spacing: Theme.Space.s) {
                                AreaDot(colorHex: area.colorHex)
                                Text(area.name)
                                Spacer()
                                if i == highlight { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(i == highlight ? Color.accentColor.opacity(0.14) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
        .frame(width: 230)
        .onAppear { focused = true }
        .onChange(of: query) { highlight = 0 }
    }

    private func pickHighlighted() {
        guard filtered.indices.contains(highlight) else { return }
        onPick(filtered[highlight])
    }
}

/// Read-only details for a Classes (or other non-Area) event.
struct ReadOnlyEventPopover: View {
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(event.summary).font(.headline)
            if event.isDeadline {
                Label(event.start.formatted(date: .abbreviated, time: .shortened), systemImage: "flag")
            } else if event.isAllDay {
                Label(event.start.formatted(date: .complete, time: .omitted), systemImage: "calendar")
            } else {
                Label("\(event.start.formatted(.dateTime.weekday(.wide).day().month())) · \(Format.timeRange(event.start, event.end))", systemImage: "clock")
            }
        }
        .font(.callout)
        .foregroundStyle(.primary)
        .padding(Theme.Space.l)
        .frame(minWidth: 220, alignment: .leading)
    }
}
