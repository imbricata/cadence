import SwiftUI
import SwiftData
import CadenceCore

struct PlanView: View {
    @Environment(GoogleService.self) private var google

    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var logs: [BlockLog]
    @Query private var entries: [BlockEntry]
    @Query private var items: [Item]

    @AppStorage("plan.mode") private var modeRaw = PlanMode.week.rawValue
    @AppStorage("plan.backlog") private var showBacklog = true

    @State private var anchor = Date.now
    @State private var selectedId: String?
    @State private var createRequest: CreateRequest?
    @State private var scrollToken = 0

    private var mode: PlanMode { PlanMode(rawValue: modeRaw) ?? .week }
    private var cal: Calendar { .current }

    private var days: [Date] {
        switch mode {
        case .day:
            return [cal.startOfDay(for: anchor)]
        case .week:
            let start = cal.dateInterval(of: .weekOfYear, for: anchor)?.start ?? cal.startOfDay(for: anchor)
            return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        }
    }

    private var title: String {
        mode == .day
            ? anchor.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : (days.first ?? anchor).formatted(.dateTime.month(.wide).year())
    }

    private var subtitle: String {
        guard mode == .week, let first = days.first, let last = days.last else { return "" }
        let sameMonth = cal.isDate(first, equalTo: last, toGranularity: .month)
        let f = first.formatted(sameMonth ? .dateTime.day() : .dateTime.day().month(.abbreviated))
        return "\(f) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    var body: some View {
        Group {
            if !google.isAuthorized && google.cachedEvents.isEmpty {
                ConnectGooglePlaceholder()
            } else {
                CalendarCanvas(
                    days: days,
                    events: google.cachedEvents,
                    areas: areas,
                    info: BlockInfoIndex(logs: logs, entries: entries, items: items),
                    selectedId: $selectedId,
                    createRequest: $createRequest,
                    scrollToken: scrollToken,
                    onSelectDay: { day in anchor = day; modeRaw = PlanMode.day.rawValue }
                )
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { shift(-1) } label: { Label("Previous", systemImage: "chevron.left").labelStyle(.iconOnly) }
                    .help("Previous (⌘←)")
                Button("Today") { goToday() }
                    .help("Go to today (⌘T)")
                Button { shift(1) } label: { Label("Next", systemImage: "chevron.right").labelStyle(.iconOnly) }
                    .help("Next (⌘→)")
            }
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $modeRaw) {
                    ForEach(PlanMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { newBlock() } label: { Label("New Block", systemImage: "plus") }
                    .help("New block (⇧⌘N)")
                Button { showBacklog.toggle() } label: { Label("Backlog", systemImage: "sidebar.right") }
                    .help("Show or hide the backlog (⌥⌘I)")
            }
        }
        .task(id: loadKey) { await ensureLoaded() }
        .inspector(isPresented: $showBacklog) {
            BacklogView().inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .focusedSceneValue(\.planActions, PlanActions(
            newBlock: newBlock,
            previous: { shift(-1) },
            next: { shift(1) },
            today: goToday,
            refresh: { Task { await google.syncNow(); await google.refreshVisible() } },
            toggleBacklog: { showBacklog.toggle() },
            setMode: { modeRaw = $0.rawValue }
        ))
    }

    // MARK: Actions

    private var loadKey: String { "\(mode.rawValue)-\(days.first?.timeIntervalSince1970 ?? 0)" }

    private func ensureLoaded() async {
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return }
        await google.ensureEvents(in: DateInterval(start: first, end: end))
    }

    private func shift(_ delta: Int) {
        let step = mode == .day ? delta : delta * 7
        anchor = cal.date(byAdding: .day, value: step, to: anchor) ?? anchor
    }

    private func goToday() {
        anchor = .now
        scrollToken += 1
    }

    /// Next free hour on the visible day (today: from now; otherwise from 09:00).
    private func newBlock() {
        let day = days.first(where: { cal.isDateInToday($0) }) ?? days.first ?? anchor
        let from: Double = cal.isDateInToday(day)
            ? EventLayout.minuteOfDay(.now, on: day)
            : 9 * 60
        let start = EventLayout.nextFreeSlot(on: day, from: from, duration: 60, events: google.events(on: day))
        createRequest = CreateRequest(day: day, startMinute: min(start, 1380))
    }
}
