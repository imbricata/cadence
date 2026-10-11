import SwiftUI
import CadenceCore

enum AppTab: String, CaseIterable {
    case today, inbox, areas
}

struct RootView: View {
    @Environment(GoogleService.self) private var google
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar") }
                .tag(AppTab.today)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(AppTab.inbox)
            AreasView()
                .tabItem { Label("Areas", systemImage: "square.grid.2x2") }
                .tag(AppTab.areas)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCapture)) { _ in
            selection = .inbox
        }
        .onOpenURL { url in
            if url.scheme == "cadence" {
                NotificationCenter.default.post(name: .openCapture, object: nil)
            }
        }
    }

    private func refresh() async {
        await google.syncNow()
        let day = Calendar.current.dateInterval(of: .day, for: .now)!
        await google.refreshEvents(start: day.start, end: day.end.addingTimeInterval(14 * 24 * 3600))
    }
}