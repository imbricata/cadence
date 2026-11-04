import SwiftUI
import SwiftData
import CadenceCore

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(InsightsModel.self) private var insights
    @Environment(\.openSettings) private var openSettings

    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var logs: [BlockLog]
    @Query private var entries: [BlockEntry]
    @Query private var items: [Item]

    @State private var date = Date()
    @State private var forward = true
    @State private var blockTarget: BlockSheetTarget?
    @State private var readOnly: CalendarEvent?
    @State private var createSlot: CreateSlot?
    @State private var showUnplanned = false
    @State private var showNewTask = false
    @State private var deleteCandidate: CalendarEvent?

    private var cal: Calendar { .current }
    private var isToday: Bool { cal.isDateInToday(date) }
    private var dayEvents: [CalendarEvent] { google.events(on: date) }

    private var title: String {
        isToday ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Days of the visible week that have Area blocks, for the dots under the week strip.
    private var busyDays: Set<Date> {
        let areaCals = Set(areas.filter { !$0.isClassesCalendar && !$0.googleCalendarId.isEmpty }.map(\.googleCalendarId))
        guard let week = cal.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return Set(google.eventStore.events(overlapping: week).filter { areaCals.contains($0.calendarId) && !$0.isAllDayLike }.map { cal.startOfDay(for: $0.start) })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if !google.isAuthorized && google.cachedEvents.isEmpty {
                    ConnectGooglePlaceholder()
                } else {
                    DayTimeline(
                        day: date, events: dayEvents, areas: areas,
                        info: BlockInfoIndex(logs: logs, entries: entries, items: items),
                        actions: actions
                    )
                    .id(cal.startOfDay(for: date))
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
                    .refreshable { await google.refreshVisible() }
                    .simultaneousGesture(daySwipe)
                    .clipped()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .statusBanner()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { openSettings() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                if !isToday {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") { go(to: .now) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNewTask = true } label: { Label("New Task", systemImage: "checklist") }
                            .disabled(!areas.contains { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar })
                        Button { newBlockAtNextFreeSlot() } label: { Label("New Block", systemImage: "plus") }
                        Button { showUnplanned = true } label: { Label("Log Time", systemImage: "clock.badge.plus") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .task(id: cal.startOfDay(for: date)) {
                if let week = cal.dateInterval(of: .weekOfYear, for: date) { await google.ensureEvents(in: week) }
            }
            #if DEBUG
            .task { await debugOpen() }
            #endif
        }
        .sheet(item: $blockTarget) { t in
            BlockDetailView(event: t.event, area: t.area)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $readOnly) { e in
            ReadOnlyEventView(event: e)
                .presentationDetents([.height(180)])
        }
        .sheet(item: $createSlot) { QuickCreateSheet(slot: $0) }
        .sheet(isPresented: $showUnplanned) { UnplannedLogSheet() }
        .sheet(isPresented: $showNewTask) { ItemEditorView() }
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Block", role: .destructive) {
                if let e = deleteCandidate { Task { await google.deleteBlock(event: e) } }
                deleteCandidate = nil
            }
        } message: { Text("It has been logged. The log stays in your history.") }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Theme.Space.s) {
            WeekStrip(selection: Binding(get: { date }, set: { go(to: $0) }), busyDays: busyDays)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) {
                    dateCaption.fixedSize()
                    Spacer(minLength: Theme.Space.m)
                    followThroughCaption.fixedSize()
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    dateCaption
                    followThroughCaption
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, Theme.Space.l)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let due = TaskAgenda.openTasks(items: items, areas: areas).filter {
                    let bucket = TaskBucket.classify(dueDate: $0.dueDate, now: context.date)
                    return bucket == .overdue || bucket == .today
                }
                if isToday && !due.isEmpty {
                    NavigationLink {
                        TasksView(initialFilter: .due)
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            Image(systemName: "checklist")
                            Text("\(due.count) \(due.count == 1 ? "task needs" : "tasks need") attention")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHint("Show overdue tasks and tasks due today")
                    .padding(.horizontal, Theme.Space.l)
                }
            }
        }
        .padding(.bottom, Theme.Space.s)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var dateCaption: some View {
        Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
            .font(.subheadline).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var followThroughCaption: some View {
        if let p = insights.snapshot.followThrough.percent {
            Text("Follow-through \(Int(p.rounded()))%")
                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private var actions: TimelineActions {
        TimelineActions(
            open: { e, a in blockTarget = BlockSheetTarget(id: e.id, event: e, area: a) },
            openReadOnly: { readOnly = $0 },
            create: { m in createSlot = CreateSlot(day: date, startMinute: m) },
            log: { e, a, state in
                logBlock(store, BlockRef(event: e, areaId: a.id), state: state)
            },
            changeArea: { e, old, new in Task { await google.changeBlockArea(event: e, from: old, to: new) } },
            delete: { e in
                if let s = BlockInfoIndex(logs: logs, entries: entries, items: items).info(for: e)?.state, s != .unlogged {
                    deleteCandidate = e
                } else {
                    Task { await google.deleteBlock(event: e) }
                }
            }
        )
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                guard abs(v.translation.width) > 80, abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                go(to: cal.date(byAdding: .day, value: v.translation.width < 0 ? 1 : -1, to: date) ?? date)
            }
    }

    private func go(to newDate: Date) {
        guard !cal.isDate(newDate, inSameDayAs: date) else { return }
        forward = newDate > date
        withAnimation(Theme.snappy) { date = newDate }
    }

    private func newBlockAtNextFreeSlot() {
        let from = isToday ? EventLayout.minuteOfDay(.now, on: date) : 9 * 60
        let m = EventLayout.nextFreeSlot(on: date, from: from, duration: 60, events: dayEvents)
        createSlot = CreateSlot(day: date, startMinute: min(m, 1380))
    }

    #if DEBUG
    /// `-CadenceSheet block|create|log` for screenshots.
    private func debugOpen() async {
        guard let what = DemoMode.arg("CadenceSheet"), what != "settings" else { return }
        try? await Task.sleep(for: .seconds(2))
        switch what {
        case "create": createSlot = CreateSlot(day: date, startMinute: 10 * 60)
        case "log": showUnplanned = true
        default:
            if let e = dayEvents.first(where: { ev in areas.first { $0.googleCalendarId == ev.calendarId }?.isClassesCalendar == false }),
               let a = areas.first(where: { $0.googleCalendarId == e.calendarId }) {
                blockTarget = BlockSheetTarget(id: e.id, event: e, area: a)
            }
        }
    }
    #endif
}
