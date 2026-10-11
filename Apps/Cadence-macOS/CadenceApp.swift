import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var store: AppStore
    @State private var google: GoogleService

    init() {
        let s = try! AppStore.live()
        _store = State(initialValue: s)
        _google = State(initialValue: GoogleService(store: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(google)
                .modelContainer(store.container)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1150, height: 720)

        Settings {
            SettingsView()
                .environment(store)
                .environment(google)
                .modelContainer(store.container)
        }
    }
}