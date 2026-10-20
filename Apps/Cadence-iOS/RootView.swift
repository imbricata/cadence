import SwiftUI
import SwiftData
import CadenceCore

enum AppTab: String, CaseIterable {
    case today, inbox, areas
}

struct RootView: View {
    @Environment(GoogleService.self) private var google
    @Environment(\.scenePhase) private var scenePhase
    @Query private var notes: [InboxNote]

    @State private var selection: AppTab = RootView.initialTab
    @State private var showSettings = RootView.initialSettings

    private var failedCount: Int { notes.filter { !$0.isDeleted && $0.state == .failed }.count }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar") }
                .tag(AppTab.today)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(failedCount)
                .tag(AppTab.inbox)
            AreasView()
                .tabItem { Label("Areas", systemImage: "square.grid.2x2") }
                .tag(AppTab.areas)
        }
        .environment(\.openSettings, { showSettings = true })
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: scenePhase, initial: true) { _, phase in google.setActive(phase == .active) }
        .toastHost()
    }

    private static var initialTab: AppTab {
        #if DEBUG
        if let raw = DemoMode.arg("CadenceTab"), let tab = AppTab(rawValue: raw) { return tab }
        #endif
        return .today
    }

    private static var initialSettings: Bool {
        #if DEBUG
        return DemoMode.arg("CadenceSheet") == "settings"
        #else
        return false
        #endif
    }
}
