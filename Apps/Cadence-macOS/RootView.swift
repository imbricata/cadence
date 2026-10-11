import SwiftUI
import CadenceCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case plan, inbox, areas, insights
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plan: return "Plan"
        case .inbox: return "Inbox"
        case .areas: return "Areas"
        case .insights: return "Insights"
        }
    }
    var icon: String {
        switch self {
        case .plan: return "calendar"
        case .inbox: return "tray"
        case .areas: return "square.grid.2x2"
        case .insights: return "chart.bar"
        }
    }
}

struct RootView: View {
    @Environment(GoogleService.self) private var google
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarSection? = .plan

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .plan: PlanView()
            case .inbox: InboxView()
            case .areas: AreasView()
            case .insights: InsightsView()
            case .none: Text("Select a section")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandNewNote)) { _ in
            selection = .inbox
        }
    }

    private func refresh() async {
        await google.syncNow()
        let day = Calendar.current.dateInterval(of: .day, for: .now)!
        await google.refreshEvents(start: day.start, end: day.end.addingTimeInterval(28 * 24 * 3600))
    }
}