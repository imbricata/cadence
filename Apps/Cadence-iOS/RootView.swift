import SwiftUI
import CadenceCore

struct RootView: View {
    @Environment(GoogleService.self) private var google
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar") }
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            AreasView()
                .tabItem { Label("Areas", systemImage: "square.grid.2x2") }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        await google.syncNow()
        let day = Calendar.current.dateInterval(of: .day, for: .now)!
        await google.refreshEvents(start: day.start, end: day.end.addingTimeInterval(14 * 24 * 3600))
    }
}