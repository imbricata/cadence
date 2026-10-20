import SwiftUI
import CadenceCore

/// Read-only details for a Classes (or other non-Area) event.
struct ReadOnlyEventView: View {
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
