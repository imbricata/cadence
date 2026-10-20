import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var store: AppStore
    @State private var google: GoogleService
    @State private var inbox: InboxService
    @State private var insights: InsightsModel

    init() {
        let s = try! AppStore.live()
        _store = State(initialValue: s)
        let g = GoogleService(store: s)
        _google = State(initialValue: g)
        _inbox = State(initialValue: InboxService(store: s))
        _insights = State(initialValue: InsightsModel(store: s, events: g.eventStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(google)
                .environment(inbox)
                .environment(insights)
                .modelContainer(store.container)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1150, height: 720)

        Settings {
            SettingsView()
                .environment(store)
                .environment(google)
                .environment(inbox)
                .environment(insights)
                .modelContainer(store.container)
        }
        .commands {
            CadenceCommands()
        }
    }
}