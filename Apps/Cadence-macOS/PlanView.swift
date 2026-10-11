import SwiftUI
import SwiftData
import CadenceCore

struct PlanView: View {
    @Environment(GoogleService.self) private var google
    @Environment(AppStore.self) private var store
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]

    @State private var weekAnchor = Date()
    @State private var showNewBlock = false
    @State private var newBlockStart = Date()
    @State private var blockTarget: BlockSheetTarget?

    var body: some View {
        Group {
            if !google.isAuthorized {
                ConnectGooglePlaceholder()
            } else {
                HStack(spacing: 0) {
                    WeekGrid(
                        week: weekAnchor,
                        events: google.cachedEvents,
                        areaFor: areaFor,
                        onOpenEvent: openEvent,
                        onCreateAt: requestCreate,
                        onMoveEvent: { event, newStart in
                            let dur = event.end.timeIntervalSince(event.start)
                            Task { await google.updateBlock(event: event, start: newStart, end: newStart.addingTimeInterval(dur), summary: nil) }
                        },
                        onResizeEvent: { event, newEnd in
                            Task { await google.updateBlock(event: event, start: nil, end: newEnd, summary: nil) }
                        },
                        onDropItem: dropItem
                    )
                    Divider()
                    BacklogView()
                        .frame(width: 300)
                }
            }
        }
        .navigationTitle(navTitle)
        .toolbar {
            ToolbarItemGroup {
                Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                Button("This week") { weekAnchor = .now }
                Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                Button { Task { await syncAndRefresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Button { requestCreate(.now) } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { Task { await syncAndRefresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .commandNewBlock)) { _ in requestCreate(.now) }
        .onReceive(NotificationCenter.default.publisher(for: .commandPrevDay)) { _ in shiftWeek(-1) }
        .onReceive(NotificationCenter.default.publisher(for: .commandNextDay)) { _ in shiftWeek(1) }
        .onReceive(NotificationCenter.default.publisher(for: .commandToday)) { _ in weekAnchor = .now }
        .onReceive(NotificationCenter.default.publisher(for: .commandSync)) { _ in Task { await syncAndRefresh() } }
        .sheet(isPresented: $showNewBlock) {
            NewBlockSheet(initialDate: newBlockStart, initialStart: newBlockStart)
        }
        .sheet(item: $blockTarget) { target in
            BlockFillLogView(event: target.event, area: target.area)
        }
    }

    private var navTitle: String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAnchor))!
        return start.formatted(.dateTime.month(.abbreviated).year())
    }

    private func shiftWeek(_ delta: Int) {
        weekAnchor = Calendar.current.date(byAdding: .day, value: delta * 7, to: weekAnchor) ?? weekAnchor
    }

    private func areaFor(_ calendarId: String) -> Area? {
        areas.first { !$0.isDeleted && $0.googleCalendarId == calendarId }
    }

    private func openEvent(_ event: CalendarEvent) {
        guard let area = areaFor(event.calendarId), !area.isClassesCalendar else { return }
        blockTarget = BlockSheetTarget(id: event.id, event: event, area: area)
    }

    private func requestCreate(_ start: Date) {
        newBlockStart = start
        showNewBlock = true
    }

    private func dropItem(_ itemId: String, _ event: CalendarEvent) {
        guard let area = areaFor(event.calendarId), !area.isClassesCalendar,
              let item = items.first(where: { $0.id.uuidString == itemId && !$0.isDeleted }) else { return }
        let planned = max(1, Int(event.end.timeIntervalSince(event.start) / 60))
        addItemToBlock(store, item: item, googleEventId: event.id, eventStart: event.start, areaId: area.id, plannedMinutes: planned)
    }

    private func syncAndRefresh() async {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAnchor))!
        await google.refreshEvents(start: cal.date(byAdding: .day, value: -7, to: start)!, end: cal.date(byAdding: .day, value: 14, to: start)!)
    }
}