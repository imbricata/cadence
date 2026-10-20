import SwiftUI
import SwiftData
import CadenceCore

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(InsightsModel.self) private var insights
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @State private var date = Date()
    @State private var blockTarget: BlockSheetTarget?
    @State private var showNewBlock = false
    @State private var showUnplanned = false

    private var dayEvents: [CalendarEvent] {
        google.events(on: date).sorted { $0.start < $1.start }
    }

    private var followThrough: Double? { insights.snapshot.followThrough.percent }

    var body: some View {
        NavigationStack {
            Group {
                if !google.isAuthorized {
                    ConnectGooglePlaceholder()
                } else if dayEvents.isEmpty {
                    ScrollView {
                        ContentUnavailableView("Nothing planned", systemImage: "calendar", description: Text(emptyDetail))
                            .padding(.top, 80)
                        Button("Refresh") { Task { await google.refreshVisible() } }
                            .buttonStyle(.bordered)
                            .padding(.top, 12)
                    }
                } else {
                    List {
                        if let ft = followThrough {
                            Section {
                                HStack {
                                    Text("Follow-through · 7 days").font(.footnote).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(ft.rounded()))%").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                        }
                        ForEach(dayEvents) { event in
                            EventRow(event: event, area: area(for: event))
                                .contentShape(Rectangle())
                                .onTapGesture { open(event) }
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
                    Menu {
                        Button { showNewBlock = true } label: { Label("New block", systemImage: "plus") }
                        Button { showUnplanned = true } label: { Label("Log time", systemImage: "clock.badge.plus") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
            }
            .refreshable { await google.refreshVisible() }
            .task(id: Calendar.current.startOfDay(for: date)) {
                if let day = Calendar.current.dateInterval(of: .day, for: date) { await google.ensureEvents(in: day) }
            }
        }
        .sheet(item: $blockTarget) { target in
            BlockDetailView(event: target.event, area: target.area)
        }
        .sheet(isPresented: $showNewBlock) {
            NewBlockSheet(initialDate: date, initialStart: date)
        }
        .sheet(isPresented: $showUnplanned) {
            UnplannedLogSheet()
        }
    }

    private var title: String {
        Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private var emptyDetail: String {
        "Nothing planned for this day."
    }

    private func dayArrow(_ symbol: String, _ delta: Int) -> some View {
        Button { date = Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date }
        label: { Image(systemName: symbol) }
    }

    private func area(for event: CalendarEvent) -> Area? {
        areas.first { !$0.isDeleted && $0.googleCalendarId == event.calendarId }
    }

    private func open(_ event: CalendarEvent) {
        guard let area = area(for: event), !area.isClassesCalendar else { return }
        blockTarget = BlockSheetTarget(id: event.id, event: event, area: area)
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