import SwiftUI
import SwiftData
import CadenceCore

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @State private var date = Date()

    private var dayEvents: [CalendarEvent] {
        google.events(on: date).sorted { $0.start < $1.start }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !google.isAuthorized {
                    ConnectGooglePlaceholder()
                } else if dayEvents.isEmpty {
                    ContentUnavailableView("Nothing planned", systemImage: "calendar", description: Text("This day is clear."))
                } else {
                    List {
                        ForEach(dayEvents) { event in
                            EventRow(event: event, area: area(for: event))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { dayArrow("chevron.left", -1) }
                ToolbarItem(placement: .topBarLeading) { Button("Today") { date = .now } }
                ToolbarItem(placement: .topBarLeading) { dayArrow("chevron.right", 1) }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
            }
            .refreshable {
                await google.refreshEvents(start: windowStart, end: windowEnd)
            }
        }
    }

    private var title: String {
        Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private var windowStart: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date
    }
    private var windowEnd: Date {
        Calendar.current.date(byAdding: .day, value: 8, to: date) ?? date
    }

    private func dayArrow(_ symbol: String, _ delta: Int) -> some View {
        Button { date = Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date }
        label: { Image(systemName: symbol) }
    }

    private func area(for event: CalendarEvent) -> Area? {
        areas.first { !$0.isDeleted && $0.googleCalendarId == event.calendarId }
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let area: Area?

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Rectangle()
                    .fill(isClasses ? Color.secondary.opacity(0.3) : Color(hex: area?.colorHex ?? "#888C96"))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .foregroundStyle(isClasses ? Color.secondary : .primary)
                if !isClasses {
                    Text(area?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(event.end, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private var isClasses: Bool { area?.isClassesCalendar == true }
}