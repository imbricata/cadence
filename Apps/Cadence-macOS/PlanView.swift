import SwiftUI
import SwiftData
import CadenceCore

struct PlanView: View {
    @Environment(GoogleService.self) private var google
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @State private var weekAnchor = Date()

    var body: some View {
        Group {
            if !google.isAuthorized {
                ConnectGooglePlaceholder()
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        WeekGrid(week: weekAnchor, events: google.cachedEvents, areaFor: areaFor)
                        Divider()
                    }
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
            }
        }
        .onAppear { Task { await syncAndRefresh() } }
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

    private func syncAndRefresh() async {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAnchor))!
        await google.refreshEvents(start: cal.date(byAdding: .day, value: -7, to: start)!, end: cal.date(byAdding: .day, value: 14, to: start)!)
    }
}